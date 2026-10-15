import SwiftUI

struct ExecutionProgressView:View {
    @ObservedObject var state:ExecutionProgressState
    let access:ActivityAccess
    let workset:String
    let missions:[ActivityCurrentItem]
    let connection:@MainActor () async->AdvisoryConnection?
    var reveal:(String)->Void={_ in}
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scene
    @FocusState private var focusedControl:String?
    private var language:String {locale.language.languageCode?.identifier ?? "en"}
    private func text(_ key:String)->String {ExecutionProgressCopy.text(key,language)}
    private var missionRows:[ActivityCurrentItem] {
        var seen=Set<String>()
        return missions.filter {row in row.mission_id.map {seen.insert($0).inserted} ?? false}
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Divider();Text(text("title")).font(.title2.bold())
            Text(text("notice")).font(.callout).foregroundStyle(.secondary)
            Picker(text("mission"),selection:Binding(get:{state.navigation.mission},set:{value in Task {await state.choose(value)}})) {
                Text(text("choose")).tag("")
                ForEach(missionRows) {row in Text(row.title).tag(row.mission_id ?? "")}
            }.focused($focusedControl,equals:"mission").id("execution-mission").accessibilityIdentifier("execution-mission")
            ProposalCompareControl(title:text("refresh"),focused:focusedControl=="refresh") {Task {await state.refresh()}}
                .focused($focusedControl,equals:"refresh").id("execution-refresh")
                .disabled(state.navigation.mission.isEmpty || state.busy).accessibilityIdentifier("execution-refresh")
            if state.busy {ProgressView().controlSize(.small)}
            Text(text(state.status)).accessibilityIdentifier("execution-status").fixedSize(horizontal:false,vertical:true)
            if let overview=state.overview {snapshot(overview)}
        }.frame(maxWidth:.infinity,alignment:.leading)
        .task(id:access.key(workset,draft:access.token)) {await activate()}
        .onDisappear {state.hide()}
        .onChange(of:focusedControl) {_,focus in if let focus {reveal(anchor(focus))}}
        .onChange(of:scene) {_,value in if value == .active {Task {await activate()}} else {state.hide()}}
    }
    private func anchor(_ focus:String)->String {
        switch focus {
        case "detail":return "execution-detail"
        case "refresh":return "execution-refresh"
        case "mission":return "execution-mission"
        default:return "execution-run-"+focus
        }
    }
    private func activate() async {
        guard scene == .active,let current=await connection() else {state.reset();return}
        let q=ExecutionQuery(connection:current,activity:access,workset:workset,mission:"")
        await state.activate(q,current:connection)
    }
    private func snapshot(_ value:ExecutionEnvelope)->some View {
        VStack(alignment:.leading,spacing:10) {
            Text(text("asOf")).font(.caption).foregroundStyle(.secondary)
            Text(text("observed")+": "+value.packet.observed_at).font(.caption)
            Text(text("updated")+": "+(value.packet.source_updated_at ?? text("UNAVAILABLE"))).font(.caption)
            Text(text("known")).font(.caption)
            if value.packet.unlinked_legacy_records>0 {Text(text("legacy")+": "+String(value.packet.unlinked_legacy_records)).font(.caption)}
            ForEach(Array(value.packet.groups.enumerated()),id:\.element.id) {index,group in
                GroupBox(text("action")+" "+String(index+1)) {
                    VStack(alignment:.leading,spacing:10) {ForEach(group.records) {row in record(row,packet:value.packet)}}
                }
            }
            if let row=state.detail {
                VStack(alignment:.leading,spacing:10) {
                    ProposalCompareControl(title:text("details"),systemImage:state.navigation.expanded ? "chevron.down":"chevron.right",focused:focusedControl=="detail") {
                        state.expanded(!state.navigation.expanded)
                        if !state.navigation.expanded {focusedControl=row.id}
                    }.focused($focusedControl,equals:"detail").id("execution-detail").accessibilityIdentifier("execution-detail")
                    if state.navigation.expanded {history(row)}
                }.onExitCommand {state.expanded(false);focusedControl=row.id}
                .task(id:row.id) {
                    // Focus only after the new detail control has mounted. Keep
                    // late focus tasks fenced to the same authorized selection.
                    let original=state.navigation
                    await Task.yield()
                    guard !Task.isCancelled,original==state.navigation,original.expanded,state.detail?.id==row.id else {return}
                    focusedControl="detail";reveal("execution-detail")
                }
            }
            DisclosureGroup(text("source")) {
                identities([("epInstance",value.packet.instance_id),("project",value.packet.selection.project_id),("authority",value.packet.selection.authority_repository_id),("forgeInstance",value.forge_instance_id),("producerSource",value.producer_source),("snapshotId",value.packet.snapshot_id)])
            }
        }
    }
    private func record(_ row:ExecutionRecord,packet:ExecutionPacket)->some View {
        VStack(alignment:.leading,spacing:7) {
            Text(row.description ?? text(row.description_status=="WITHHELD_PRIVACY" ? "withheld":"noDescription")).font(.headline).fixedSize(horizontal:false,vertical:true)
            Text(text("missionRevision")+": "+row.mission_revision).font(.caption)
            if row.lineage?.retry_parent_submission_id != nil || row.lineage?.retry_parent_run_id != nil {Label(text("retry"),systemImage:"arrow.triangle.branch").font(.caption)}
            Text(text("submissionState")+": "+text(row.submission_disposition)).font(.caption)
            Text(text(row.progress.current_phase ?? "UNAVAILABLE"))
            Text(text(row.progress.activity)).font(.caption)
            if row.progress.wait_reason != "NOT_RECORDED" {Label(text(row.progress.wait_reason),systemImage:"pause.circle").fixedSize(horizontal:false,vertical:true)}
            Text(text(row.progress.responsible_role)).font(.caption).foregroundStyle(.secondary)
            Text(text("technicalOutcome")+": "+text(row.result.technical_outcome)).font(.callout)
            Text(text("requiredValidation")+": "+text(row.result.qualification.required_validation_state)).font(.caption)
            Text(text("runQualification")+": "+text(row.result.qualification.run_qualification)).font(.caption)
            ProposalCompareControl(title:runTitle(row,packet:packet),focused:focusedControl==row.id) {
                Task {
                    await state.select(row.id)
                    // The mounted detail owns the guarded focus transition.
                }
            }.focused($focusedControl,equals:row.id).id("execution-run-"+row.id).accessibilityIdentifier("execution-run-"+row.id)
            if state.navigation.submission==row.id,(state.navigation.run==nil || state.navigation.run==row.run_id),state.navigation.group==ActivityWire.hash(Data(row.groupKey.utf8)) {Label(text("details"),systemImage:"checkmark.circle").font(.caption)}
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary,in:RoundedRectangle(cornerRadius:12))
    }
    private func runTitle(_ row:ExecutionRecord,packet:ExecutionPacket)->String {
        guard row.run_id != nil else {return row.submission_disposition=="QUEUED" ? text("queuedItem"):text("noRun")+" · "+text(row.submission_disposition)}
        return text("run")+" "+String((packet.records.firstIndex(where:{$0.id==row.id}) ?? 0)+1)
    }
    private func identities(_ fields:[(String,String?)])->some View {
        VStack(alignment:.leading,spacing:6) {
            ForEach(Array(fields.enumerated()),id:\.offset) {_,field in
                VStack(alignment:.leading) {
                    Text(text(field.0)).font(.caption.bold())
                    Text(verbatim:field.1 ?? text("UNAVAILABLE")).font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                }
            }
        }
    }
    private func history(_ row:ExecutionRecord)->some View {
        VStack(alignment:.leading,spacing:8) {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:150),alignment:.leading)],alignment:.leading) {
                ForEach(Array(row.progress.steps.enumerated()),id:\.offset) {_,step in
                    VStack(alignment:.leading) {Text(text(step.phase)).font(.caption.bold());Text(text(step.state)).font(.caption)}
                }
            }
            if row.progress.history_completeness=="UNAVAILABLE" {Text(text("UNAVAILABLE")).font(.caption)}
            ForEach(Array(row.progress.history.enumerated()),id:\.offset) {_,event in
                VStack(alignment:.leading) {Text(text(event.phase));Text(text(event.responsible_role)).font(.caption);Text(text(event.wait_reason)).font(.caption);Text(event.recorded_at ?? text("UNAVAILABLE")).font(.caption).foregroundStyle(.secondary)}
            }
            DisclosureGroup(text("source")) {
                identities([("producer",row.producer_id),("mission",row.mission_id),("missionRevision",row.mission_revision),("action",row.engineering_action_id),("submission",row.submission_id),("run",row.run_id),("attempt",row.lineage?.attempt_submission_id),("root",row.lineage?.root_submission_id),("parentRun",row.lineage?.retry_parent_run_id),("parentSubmission",row.lineage?.retry_parent_submission_id),("acceptanceSubmission",row.provenance.acceptance_submission_id),("receipt",row.provenance.acceptance_receipt_id)])
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
