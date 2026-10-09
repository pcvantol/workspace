import Foundation
import Combine

@MainActor final class MissionConceptState: ObservableObject {
    @Published private(set) var capability: AdvisoryCapability?
    @Published private(set) var history: [MissionConceptTurnRecord] = []
    @Published private(set) var items: [MissionConceptCatalogItem] = []
    @Published private(set) var pending: MissionTransportIntent?
    @Published private(set) var busy = false
    @Published private(set) var phase = "connection"
    @Published private(set) var revision = 0
    @Published private(set) var packet:MissionPreparedPacket?
    @Published private(set) var approval:MissionCompoundReadback?
    private let credentials: any AdvisoryCredentials
    private let store: any MissionIntentStore
    private let transport: MissionConceptTransport
    private var connection: AdvisoryConnection?
    private var epoch = 0
    init(credentials: any AdvisoryCredentials = AdvisoryKeychain(mission:true), store: any MissionIntentStore = PrivateMissionIntentStore(), transport: MissionConceptTransport = MissionConceptTransport()) {
        self.credentials=credentials;self.store=store;self.transport=transport
    }
    func invalidate() {
        epoch &+= 1;connection=nil;packet=nil;approval=nil;capability=nil;history=[];items=[];busy=false;revision=0;pending=nil;phase="connection"
    }
    private func admit(_ c: AdvisoryConnection?) -> Bool {
        guard let c else { invalidate();return false }
        if connection != c { invalidate();connection=c }
        return true
    }
    private func access(_ c: AdvisoryConnection) throws -> AdvisoryAccess {
        guard let a=try credentials.loadAccess(),a.validForMission,a.endpoint==c.endpoint,a.workspaceInstanceID==c.workspaceInstanceID,
              a.workspaceProjectID==c.workspaceProjectID,a.actorID==c.actorID,a.conversationIDs.contains(c.conversationID) else { throw AdvisoryError.denied }
        return a
    }
    func saveGrant(_ token:String,workspace own:AdvisoryConnection?) async {
        guard !busy,pending==nil,let own,token.range(of:"^[A-Za-z0-9_-]{43}$",options:.regularExpression) != nil else { return }
        let generation=epoch;busy=true;defer { if epoch==generation { busy=false } }
        do {
            let a=try await transport.probe(own,token:token)
            guard epoch==generation else { return }
            try credentials.saveAccess(a)
            busy=false;await refresh(producerConnection(own))
        } catch { if epoch==generation { fail(error) } }
    }
    func producerConnection(_ own:AdvisoryConnection?,id:String?=nil) -> AdvisoryConnection? {
        guard let own,let a=try? credentials.loadAccess(),a.validForMission,a.endpoint==own.endpoint,
              a.workspaceInstanceID==own.workspaceInstanceID,a.workspaceProjectID==own.workspaceProjectID,a.actorID==own.actorID,
              let source=id ?? a.conversationIDs.first,a.conversationIDs.contains(source) else { return nil }
        return .init(endpoint:own.endpoint,workspaceInstanceID:own.workspaceInstanceID,actorID:own.actorID,
            workspaceProjectID:own.workspaceProjectID,conversationID:source,bearer:own.bearer,draftGrant:own.draftGrant)
    }
    func resolveWorkspace(_ own:AdvisoryConnection) async -> AdvisoryConnection? {
        guard own.conversationID.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil,let control=producerConnection(own) else { return nil }
        let generation=epoch
        do {
            let a=try access(control)
            let resolved=try await transport.resolve(a,control,workspaceDraftID:own.conversationID,
                operationID:"resolve-"+CandidateLocal.scopeKey(own),workspaceConversationID:own.conversationID)
            guard epoch==generation else { return nil }
            return producerConnection(own,id:resolved.producerConversationID)
        } catch { if epoch==generation { fail(error) };return nil }
    }
    private func fail(_ error: Error) {
        packet=nil;approval=nil;capability=nil;history=[];items=[];revision=0
        switch error {
        case AdvisoryError.denied:phase="denied"
        case AdvisoryError.invalid:phase="invalid"
        case AdvisoryError.state(let code):
            phase=code.contains("STALE") || code.contains("CHANGED") || code.contains("CONFLICT") ? "stale" : code.contains("BUDGET") || code.contains("CAPACITY") ? "budget" : "connection"
        default:phase=pending == nil ? "connection":"pending"
        }
    }
    func canRefine(_ text: String, lens: String) -> Bool {
        guard let c=connection,let capability,!busy,pending==nil,
              capability.conversation_ids.contains(c.conversationID), capability.supported_modes.contains(lens),
              capability.retained_principal_consumed_turns<capability.maximum_turns else { return false }
        return !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && text.unicodeScalars.count<=1000
    }
    private func accept(_ observation: MissionConceptObservation, intent: MissionTransportIntent) throws {
        revision=observation.currentRevision
        if observation.turn.execution == "MAY_HAVE_HAPPENED" { phase="pending";return }
        try store.clear(intent.key);pending=nil
        phase=observation.turn.status == "COMPLETE" ? "current":"failed"
    }
    func refresh(_ new: AdvisoryConnection?) async {
        guard admit(new),!busy,let c=new else { return }
        let generation=epoch;busy=true;defer { if epoch==generation { busy=false } }
        do {
            let a=try access(c),key=CandidateLocal.scopeKey(c)
            pending=try store.load(key)
            if let p=pending {
                guard p.matches(c) else { throw AdvisoryError.denied }
                if p.kind=="approve",let body=p.approvalBody {
                    let request=try AdvisoryWire.object(body)
                    do {
                        let value=try await transport.operation(a,c,id:request["operation_id"] as! String,expectedDigest:request["package_digest"] as? String)
                        guard epoch==generation else { return };approval=value
                        if value.state=="COMPLETE" { try store.clear(p.key);pending=nil;phase=value.presentationState }
                        else { phase="pending" }
                    } catch AdvisoryError.missing { phase="pending" }
                }
                if let request=p.refine {
                    do {
                        let value=try await transport.turn(a,c,request:request)
                        guard epoch==generation else { return };try accept(value,intent:p)
                    } catch AdvisoryError.missing { phase="pending" }
                }
            }
            // A completed receipt is historical; every refresh rechecks its current definition.
            if pending == nil,let previous=approval {
                let raw=try AdvisoryWire.object(previous.data)
                let current=try await transport.operation(a,c,id:previous.operationID,expectedDigest:raw["package_digest"] as? String)
                guard epoch==generation else { return };approval=current
            }
            let cap=try await transport.capability(a,c)
            var turns:[MissionConceptTurnRecord]=[];var conversationRevision=0
            do {
                var cursor=0
                while true {
                    let page=try await transport.history(a,c,cursor:cursor)
                    guard epoch==generation else { return }
                    if cursor>0 && page.revision != conversationRevision { throw AdvisoryError.state("CONVERSATION_OR_CONTEXT_STALE") }
                    conversationRevision=page.revision;turns += page.turns
                    guard let next=page.next_cursor else { break }
                    guard next>cursor,turns.count<=8 else { throw AdvisoryError.invalid };cursor=next
                }
            } catch AdvisoryError.missing { turns=[] }
            var catalog:[MissionConceptCatalogItem]=[],rawItems:[Any]=[],snapshot:String?,cursor=0
            while true {
                let page=try await transport.catalog(a,c,cursor:cursor,snapshot:snapshot)
                guard epoch==generation else { return }
                snapshot=page.snapshot_revision;catalog += page.items
                rawItems += try JSONSerialization.jsonObject(with:page.itemsJSONData!) as! [Any]
                guard let next=page.next_cursor else { break }
                guard next>cursor,catalog.count<=a.conversationIDs.count else { throw AdvisoryError.invalid };cursor=next
            }
            guard let snapshot,try AdvisoryWire.digest(rawItems)==snapshot,Set(catalog.map(\.object_id)).count==catalog.count,
                  Set(turns.map { $0.request.turn_id }).count==turns.count else { throw AdvisoryError.invalid }
            for item in catalog {
                for edge in item.edges {
                    guard let predecessor=catalog.first(where: { $0.object_id==edge.source_object_id }),predecessor.canonical_history.contains(where: {
                        $0.definition_revision==edge.source_definition_revision && $0.candidate_id==edge.candidate_id && $0.subject_revision==edge.subject_revision && $0.subject_current
                    }) else { throw AdvisoryError.invalid }
                }
            }
            guard epoch==generation else { return }
            capability=cap;history=turns;items=catalog;revision=conversationRevision
            if let packet,!catalog.contains(where: { $0.object_id==packet.objectID && $0.revision==packet.revision && $0.definition==packet.definition }) { self.packet=nil }
            phase=pending != nil ? "pending" : approval?.presentationState ?? "current"
        } catch { if epoch==generation { fail(error) } }
    }
    func refine(_ text: String, lens: String, connection c: AdvisoryConnection?) async {
        guard admit(c),canRefine(text,lens:lens),let c else { return }
        let generation=epoch;busy=true;defer { if epoch==generation { busy=false } }
        do {
            let a=try access(c),context=try await transport.context(a,c)
            guard epoch==generation else { return }
            let request=AdvisoryRequest(contract_version:MissionConceptWire.contract,turn_id:UUID().uuidString.lowercased(),instance_id:a.forgeInstanceID,
                project_id:a.forgeProjectID,repository_id:a.repositoryID,conversation_id:c.conversationID,advisor_kind:lens,objective:text,
                expected_revision:revision,context_revision:context.revision,selected_sources:[])
            let intent=MissionTransportIntent(key:CandidateLocal.scopeKey(c),connectionScope:MissionTransportIntent.scope(c),kind:"refine",refine:request,approvalBody:nil,frozenPackage:nil)
            try store.save(intent);pending=intent
            let value=try await transport.submit(a,c,request:request)
            guard epoch==generation else { return };try accept(value,intent:intent)
            busy=false;await refresh(c)
        } catch {
            if epoch==generation {
                // A failed directory sync may leave the original record. Preserve it before retry.
                pending=(try? store.load(CandidateLocal.scopeKey(c))) ?? pending
                fail(error)
            }
        }
    }
    func resume(_ c: AdvisoryConnection?) async {
        guard admit(c),!busy,let c,let p=try? store.load(CandidateLocal.scopeKey(c)),p.matches(c) else { return }
        pending=p
        if p.kind=="approve",let body=p.approvalBody {
            let generation=epoch;busy=true;defer { if epoch==generation { busy=false } }
            do {
                let a=try access(c),request=try AdvisoryWire.object(body)
                let id=request["operation_id"] as! String,digest=request["package_digest"] as! String
                let value:MissionCompoundReadback
                do { value=try await transport.operation(a,c,id:id,expectedDigest:digest) }
                catch AdvisoryError.missing {
                    let package=try await transport.package(a,c,revision:request["revision"] as? Int)
                    guard epoch==generation,connection==c else { return }
                    guard package.digest==digest else { throw AdvisoryError.state("CONCEPT_OR_CONTEXT_CHANGED") }
                    _ = try await transport.approve(a,c,body:body,packet:package)
                    value=try await transport.operation(a,c,id:id,expectedDigest:digest)
                }
                guard epoch==generation else { return };approval=value
                if value.state=="COMPLETE" { try store.clear(p.key);pending=nil;phase=value.presentationState }
                else { phase="pending" }
            } catch { if epoch==generation { fail(error) } }
            return
        }
        guard let request=p.refine else { return }
        let generation=epoch;busy=true;defer { if epoch==generation { busy=false } }
        do {
            let a=try access(c);pending=p
            do {
                let observed=try await transport.turn(a,c,request:request)
                guard epoch==generation else { return };try accept(observed,intent:p)
            } catch AdvisoryError.missing {
                guard epoch==generation,connection==c else { return }
                let observed=try await transport.submit(a,c,request:request)
                guard epoch==generation else { return };try accept(observed,intent:p)
            }
            busy=false;await refresh(c)
        } catch { if epoch==generation { fail(error) } }
    }
    func prepare(_ card:MissionDefinitionCard,connection c:AdvisoryConnection?) async {
        guard !busy,let c,connection==c,let item=items.first(where: { $0.object_id==card.id && $0.revision==card.revision }),item.conversation_id==c.conversationID else { return }
        let generation=epoch;busy=true;defer { if epoch==generation { busy=false } }
        do {
            let a=try access(c),value=try await transport.package(a,c,revision:card.revision)
            guard epoch==generation else { return }
            guard value.objectID==card.id,value.definition==item.definition else { throw AdvisoryError.invalid }
            packet=value
            if let approval,let original=try? AdvisoryWire.object(approval.frozenPackageData)["source"] as? [String:Any],
               original["object_id"] as? String==card.id,original["revision"] as? Int==card.revision,approval.state=="COMPLETE" {
                // A read/selection cannot create a new confirmation for the same completed definition.
            } else { approval=nil }
        } catch { if epoch==generation { fail(error) } }
    }
    func canApprove(_ card:MissionDefinitionCard) -> Bool {
        guard !busy,pending==nil,capability?.approval_supported==true,capability?.supported_operations?.contains("APPROVE")==true,let packet,packet.objectID==card.id,packet.revision==card.revision,packet.packageData != nil,packet.questions.isEmpty else { return false }
        return approval?.state != "COMPLETE"
    }
    func approve(_ card:MissionDefinitionCard,connection c:AdvisoryConnection?) async {
        guard canApprove(card),let c,connection==c,let packet,let digest=packet.digest else { return }
        let generation=epoch;busy=true;defer { if epoch==generation { busy=false } }
        do {
            let a=try access(c)
            let body=try JSONSerialization.data(withJSONObject:["contract_version":MissionConceptWire.contract,"operation_id":UUID().uuidString.lowercased(),"revision":card.revision,"package_digest":digest,"confirm":true])
            let intent=MissionTransportIntent(key:CandidateLocal.scopeKey(c),connectionScope:MissionTransportIntent.scope(c),kind:"approve",refine:nil,approvalBody:body,frozenPackage:nil)
            try store.save(intent);pending=intent
            _ = try await transport.approve(a,c,body:body,packet:packet)
            guard epoch==generation else { return }
            let request=try AdvisoryWire.object(body)
            let current=try await transport.operation(a,c,id:request["operation_id"] as! String,expectedDigest:digest)
            guard epoch==generation else { return };approval=current
            if current.state=="COMPLETE" { try store.clear(intent.key);pending=nil;phase=current.presentationState }
            else { phase="pending" }
        } catch { if epoch==generation { pending=(try? store.load(CandidateLocal.scopeKey(c))) ?? pending;fail(error) } }
    }
    func presentation(project: String) -> MissionWorkspaceObservation? {
        guard let connection,capability != nil else { return nil }
        let cards=items.map { item -> MissionDefinitionCard in
            var card=MissionDefinitionCard(id:item.object_id,revision:item.revision,title:item.title,value:item.definition.business_value,outcome:item.definition.expected_result,
                scope:item.definition.scope,exclusions:item.definition.exclusions,criteria:item.definition.acceptance_criteria,questions:item.questions,
                changes:[item.definition.change_summary],group:"",labels:item.labels,status:item.state,objective:item.definition.objective,
                architectureChoices:item.definition.architecture_choices,risks:item.definition.risks,blockers:item.blockers,components:item.definition.components,suggestedResults:item.definition.possible_subresults,canonicalHistory:item.canonical_history)
            if let packet,packet.objectID==item.object_id,packet.revision==item.revision,let data=packet.packageData,
               let raw=try? AdvisoryWire.object(data),let effects=raw["consequences"] as? [String:Any],let effect=effects["repository_effect"] as? [String:Any] {
                card.consequences=[effect["mode"] as? String ?? "",effect["delivery"] as? String ?? ""]
                card.remainingDecisions=effects["human_gates"] as? [String]
            }
            if let approval,let frozen=try? AdvisoryWire.object(approval.frozenPackageData),let source=frozen["source"] as? [String:Any],
               source["object_id"] as? String==item.object_id,source["revision"] as? Int==item.revision {
                card.status=approval.presentationState
                card.physicalExecutionReady=approval.readiness?.execution_ready
                card.blockers=approval.readiness?.blockers
            }
            return card
        }
        let lines=history.flatMap { turn -> [MissionChatLine] in
            var messages=[MissionChatLine(id:turn.request.turn_id+"-user",role:"USER",text:turn.request.objective)]
            if let output=turn.outcome?.output {
                messages.append(MissionChatLine(id:turn.request.turn_id+"-advisor",role:turn.request.advisor_kind,text:output.definition.change_summary))
            }
            return messages
        }
        let relations=items.flatMap { item in item.edges.map { edge in
            MissionRelation(predecessor:edge.source_object_id,dependent:edge.target_object_id,reason:edge.reason,proposed:edge.state=="PROPOSED",sourceRevision:edge.source_definition_revision)
        } }
        let projectScope=AdvisoryConnection(endpoint:connection.endpoint,workspaceInstanceID:connection.workspaceInstanceID,actorID:connection.actorID,workspaceProjectID:connection.workspaceProjectID,conversationID:"",bearer:"",draftGrant:"")
        return MissionWorkspaceObservation(scopeKey:CandidateLocal.scopeKey(projectScope),project:project,cards:cards,relations:relations,complete:false,transcript:lines)
    }
}
