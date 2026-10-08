import Foundation
import CryptoKit
import CoreFoundation

enum AdvisoryWire {
    static let schemaData = Data(###"{"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://forge.local/api/advisory-conversation-v1.json","title":"Scoped textual advisory conversation","oneOf":[{"$ref":"#/$defs/request"},{"$ref":"#/$defs/submit"},{"$ref":"#/$defs/turn"},{"$ref":"#/$defs/history"},{"$ref":"#/$defs/cancel_request"},{"$ref":"#/$defs/cancel"},{"$ref":"#/$defs/capability"},{"$ref":"#/$defs/error"}],"$defs":{"source":{"type":"object","additionalProperties":false,"required":["source_id","version"],"properties":{"source_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"version":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"}}},"source_metadata":{"type":"object","additionalProperties":false,"required":["source_id","state","repository","revision","path","content_digest","version"],"properties":{"source_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"state":{"const":"ACTIVE"},"repository":{"type":"string"},"revision":{"type":"string","pattern":"^[0-9a-f]{40}$"},"path":{"type":"string"},"content_digest":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"version":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"}}},"request":{"type":"object","additionalProperties":false,"required":["contract_version","turn_id","instance_id","project_id","repository_id","conversation_id","advisor_kind","objective","expected_revision","context_revision","selected_sources"],"properties":{"contract_version":{"const":"forge-advisory-conversation/v1"},"turn_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"instance_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"project_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"repository_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"conversation_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"advisor_kind":{"enum":["BUSINESS","ARCHITECTURE"]},"objective":{"type":"string","minLength":1,"maxLength":1000},"expected_revision":{"type":"integer","minimum":0},"context_revision":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"selected_sources":{"type":"array","maxItems":2,"items":{"$ref":"#/$defs/source"}}}},"provider":{"type":"object","additionalProperties":false,"required":["provider_id","requested_model","requested_profile","requested_effort","policy_digest","generation_digest","configuration_revision","input_token_bound","context_token_bound","output_token_bound"],"properties":{"provider_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"requested_model":{"anyOf":[{"type":"string"},{"type":"null"}]},"requested_profile":{"anyOf":[{"type":"string"},{"type":"null"}]},"requested_effort":{"const":"NOT_CONFIGURED"},"policy_digest":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"generation_digest":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"configuration_revision":{"type":"integer","minimum":1},"input_token_bound":{"type":"integer","minimum":1},"context_token_bound":{"type":"integer","minimum":1},"output_token_bound":{"type":"integer","minimum":1}}},"diagnostic":{"type":"object","additionalProperties":false,"required":["classification","process_started","exception_type","errno","timed_out","elapsed_milliseconds","returncode","error_category","terminal_events"],"properties":{"classification":{"enum":["NOT_STARTED","REJECTED_BEFORE_GENERATION","MAY_HAVE_HAPPENED","COMPLETED_VALID","COMPLETED_CONTRACT_INVALID"]},"process_started":{"type":"boolean"},"exception_type":{"anyOf":[{"type":"string"},{"type":"null"}]},"errno":{"anyOf":[{"type":"integer"},{"type":"null"}]},"timed_out":{"type":"boolean"},"elapsed_milliseconds":{"anyOf":[{"type":"integer","minimum":0},{"type":"null"}]},"returncode":{"anyOf":[{"type":"integer"},{"type":"null"}]},"error_category":{"anyOf":[{"type":"string"},{"type":"null"}]},"terminal_events":{"type":"array","items":{"type":"string"}}}},"output":{"type":"object","additionalProperties":false,"required":["contract_version","request_digest","advisor_kind","summary","alternatives","questions","suggestions","evidence_references","applied"],"properties":{"contract_version":{"const":"forge-advisory-conversation/v1"},"request_digest":{"type":"string"},"advisor_kind":{"enum":["BUSINESS","ARCHITECTURE"]},"summary":{"type":"string","minLength":1,"maxLength":512},"alternatives":{"type":"array","maxItems":4,"items":{"type":"string","minLength":1,"maxLength":256}},"questions":{"type":"array","maxItems":4,"items":{"type":"string","minLength":1,"maxLength":256}},"suggestions":{"type":"array","maxItems":4,"items":{"type":"string","minLength":1,"maxLength":256}},"evidence_references":{"type":"array","maxItems":4,"items":{"type":"string","minLength":1,"maxLength":256}},"applied":{"const":false}}},"outcome":{"type":"object","additionalProperties":false,"required":["execution","diagnostic","usage","usage_status","observed_model","observed_effort","output","result_digest","error_code"],"properties":{"execution":{"enum":["NOT_STARTED","MAY_HAVE_HAPPENED","CONFIRMED"]},"diagnostic":{"$ref":"#/$defs/diagnostic"},"usage":{"anyOf":[{"type":"object","additionalProperties":false,"required":["input_tokens","output_tokens"],"properties":{"input_tokens":{"type":"integer","minimum":0},"output_tokens":{"type":"integer","minimum":0}}},{"type":"null"}]},"usage_status":{"enum":["NOT_REPORTED","OBSERVED"]},"observed_model":{"const":"NOT_REPORTED"},"observed_effort":{"const":"NOT_REPORTED"},"output":{"anyOf":[{"$ref":"#/$defs/output"},{"type":"null"}]},"result_digest":{"anyOf":[{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},{"type":"null"}]},"error_code":{"anyOf":[{"enum":["ADVICE_RESULT_INVALID","ADVICE_USAGE_NOT_REPORTED","ADVICE_USAGE_BOUND_EXCEEDED","ADVICE_PROVIDER_UNAVAILABLE"]},{"type":"null"}]}}},"context":{"type":"object","additionalProperties":false,"required":["instance_id","project_id","repository_id","dataset_generation","included_sources","selected_sources","missing_sources","freshness","evidence_references","limitations"],"properties":{"instance_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"project_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"repository_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"dataset_generation":{"type":"integer","minimum":0},"included_sources":{"type":"array","items":{"type":"string"}},"selected_sources":{"type":"array","items":{"$ref":"#/$defs/source"},"maxItems":2},"missing_sources":{"type":"array","items":{"type":"string"}},"freshness":{"const":"CURRENT_CONFIGURED_BINDING"},"evidence_references":{"type":"array","items":{"type":"string"},"maxItems":3},"limitations":{"type":"array","items":{"type":"string"}}}},"turn_record":{"type":"object","additionalProperties":false,"required":["request","request_digest","session_id","invocation_id","context","provider","status","lifecycle","execution","outcome","admitted_at","grant_id","consumption"],"properties":{"request":{"$ref":"#/$defs/request"},"request_digest":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"session_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"invocation_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"context":{"$ref":"#/$defs/context"},"provider":{"$ref":"#/$defs/provider"},"status":{"enum":["REASONING","REVIEW","COMPLETE","FAILED","CANCEL_REQUESTED"]},"lifecycle":{"type":"array","minItems":3,"maxItems":5,"items":{"enum":["CREATED","PREPARED","REASONING","REVIEW","COMPLETE"]}},"execution":{"enum":["NOT_STARTED","MAY_HAVE_HAPPENED","CONFIRMED"]},"outcome":{"anyOf":[{"$ref":"#/$defs/outcome"},{"type":"null"}]},"admitted_at":{"type":"string","format":"date-time"},"grant_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"consumption":{"const":1}}},"submit":{"type":"object","additionalProperties":false,"required":["contract_version","recorded","original_turn","current_revision"],"properties":{"contract_version":{"const":"forge-advisory-conversation/v1"},"recorded":{"type":"boolean"},"original_turn":{"$ref":"#/$defs/turn_record"},"current_revision":{"type":"integer","minimum":0}}},"turn":{"type":"object","additionalProperties":false,"required":["contract_version","original_turn","current_revision","read_only"],"properties":{"contract_version":{"const":"forge-advisory-conversation/v1"},"original_turn":{"$ref":"#/$defs/turn_record"},"current_revision":{"type":"integer","minimum":0},"read_only":{"const":true}}},"history":{"type":"object","additionalProperties":false,"required":["contract_version","conversation_id","scope","revision","turns","next_cursor","consumed_turns","maximum_turns","retention","read_only"],"properties":{"contract_version":{"const":"forge-advisory-conversation/v1"},"conversation_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"scope":{"type":"object","additionalProperties":false,"required":["instance_id","project_id","repository_id"],"properties":{"instance_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"project_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"repository_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"}}},"revision":{"type":"integer","minimum":0},"turns":{"type":"array","maxItems":4,"items":{"$ref":"#/$defs/turn_record"}},"next_cursor":{"anyOf":[{"type":"integer","minimum":0},{"type":"null"}]},"consumed_turns":{"type":"integer","minimum":0},"maximum_turns":{"type":"integer","minimum":1,"maximum":8},"retention":{"const":"PRIVATE_RETAINED_NO_AUTOMATIC_DELETE"},"read_only":{"const":true}}},"cancel_request":{"type":"object","additionalProperties":false,"required":["contract_version","expected_revision","request_digest"],"properties":{"contract_version":{"const":"forge-advisory-conversation/v1"},"expected_revision":{"type":"integer","minimum":0},"request_digest":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"}}},"cancel":{"type":"object","additionalProperties":false,"required":["contract_version","original_turn","current_revision","provider_stopped","cancel_request_recorded"],"properties":{"contract_version":{"const":"forge-advisory-conversation/v1"},"original_turn":{"$ref":"#/$defs/turn_record"},"current_revision":{"type":"integer","minimum":0},"provider_stopped":{"const":false},"cancel_request_recorded":{"const":true}}},"capability":{"type":"object","additionalProperties":false,"required":["contract_version","supported_modes","unsupported","project_id","repository_id","instance_id","conversation_ids","context","context_revision","maximum_turns","available_sources","max_concurrent_invocations_per_instance","cancel_request_supported","provider_stop_supported","retained_principal_consumed_turns","live_model_quality","unknown_usage","read_only"],"properties":{"contract_version":{"const":"forge-advisory-conversation/v1"},"supported_modes":{"type":"array","items":{"enum":["BUSINESS","ARCHITECTURE"]}},"unsupported":{"type":"array","items":{"type":"string"}},"project_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"repository_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"instance_id":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"},"conversation_ids":{"type":"array","minItems":1,"maxItems":16,"items":{"type":"string","minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"}},"context":{"$ref":"#/$defs/context"},"context_revision":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"maximum_turns":{"type":"integer","minimum":1,"maximum":8},"available_sources":{"type":"array","maxItems":16,"items":{"$ref":"#/$defs/source_metadata"}},"max_concurrent_invocations_per_instance":{"const":1},"cancel_request_supported":{"const":true},"provider_stop_supported":{"const":false},"retained_principal_consumed_turns":{"type":"integer","minimum":0},"live_model_quality":{"const":"NOT_QUALIFIED"},"unknown_usage":{"const":"NOT_REPORTED_AND_NOT_ACCEPTED_AS_BOUND_PROOF"},"read_only":{"const":true}}},"error":{"type":"object","additionalProperties":false,"required":["contract_version","error"],"properties":{"contract_version":{"const":"forge-advisory-conversation/v1"},"error":{"type":"object","additionalProperties":false,"required":["code"],"properties":{"code":{"enum":["ADVISORY_SCOPE_DENIED","ADVISORY_CONFLICT","ADVISORY_NOT_FOUND","ADVISORY_REQUEST_INVALID","ADVISORY_SOURCE_UNAVAILABLE","ADVISORY_ROUTE_NOT_FOUND","CONVERSATION_BUSY","TRANSCRIPT_CAPACITY_EXHAUSTED","TURN_PAYLOAD_CONFLICT","CONVERSATION_OR_CONTEXT_STALE","INVOCATION_UNRESOLVED","TURN_BUDGET_EXHAUSTED","TRANSCRIPT_CAPACITY_EXHAUSTED","CONVERSATION_CAPACITY_EXHAUSTED","CANCEL_PRECONDITION_CHANGED","ADVISOR_UNSUPPORTED","CONTEXT_STALE","ADVISORY_PROVIDER_UNAVAILABLE"]}}}}}}}"###.utf8)
    static var schema: [String:Any] { try! JSONSerialization.jsonObject(with:schemaData) as! [String:Any] }
    static let contract = "forge-advisory-conversation/v1"
    static func validate(_ value: Any, kind: String) throws {
        let defs=schema["$defs"] as! [String:Any]
        try check(value, defs[kind] as! [String:Any])
    }
    private static func check(_ value: Any, _ rules: [String:Any]) throws {
        if let ref=rules["$ref"] as? String { return try validate(value,kind:ref.components(separatedBy:"/").last!) }
        for union in ["oneOf","anyOf"] {
            if let options=rules[union] as? [[String:Any]] {
                let matches=options.filter { (try? check(value,$0)) != nil }.count
                guard matches>0 && (union != "oneOf" || matches==1) else { throw AdvisoryError.invalid }
                return
            }
        }
        if let type=rules["type"] as? String { try scalar(value,type) }
        if let constant=rules["const"] {
            guard NSDictionary(dictionary:["v":value]).isEqual(to:["v":constant]), boolean(value)==boolean(constant) else { throw AdvisoryError.invalid }
        }
        if let values=rules["enum"] as? [String] { guard let v=value as? String, values.contains(v) else { throw AdvisoryError.invalid };return }
        if let obj=value as? [String:Any] {
            let properties=rules["properties"] as? [String:[String:Any]] ?? [:]
            guard Set(rules["required"] as? [String] ?? []).isSubset(of:Set(obj.keys)),
                (rules["additionalProperties"] as? Bool) != false || Set(obj.keys).isSubset(of:Set(properties.keys)) else { throw AdvisoryError.invalid }
            for (k,v) in obj { try check(v,properties[k] ?? [:]) }
        } else if let items=value as? [Any] {
            guard items.count >= (rules["minItems"] as? Int ?? 0), items.count <= (rules["maxItems"] as? Int ?? 64) else { throw AdvisoryError.invalid }
            for v in items { try check(v,rules["items"] as? [String:Any] ?? [:]) }
        } else if let text=value as? String {
            guard text.unicodeScalars.count >= (rules["minLength"] as? Int ?? 0), text.unicodeScalars.count <= (rules["maxLength"] as? Int ?? 4096) else { throw AdvisoryError.invalid }
            if let pattern=rules["pattern"] as? String { guard text.range(of:pattern,options:.regularExpression)?.lowerBound==text.startIndex else { throw AdvisoryError.invalid } }
            if rules["format"] as? String == "date-time" { guard text.count<=64, time(text) else { throw AdvisoryError.invalid } }
        } else if let number=value as? NSNumber, !boolean(value) {
            guard number.int64Value >= (rules["minimum"] as? Int64 ?? Int64.min), number.int64Value <= (rules["maximum"] as? Int64 ?? Int64.max) else { throw AdvisoryError.invalid }
        }
    }
    private static func boolean(_ value: Any) -> Bool { guard let n=value as? NSNumber else { return false };return CFGetTypeID(n)==CFBooleanGetTypeID() }
    private static func scalar(_ value: Any, _ type: String) throws {
        let valid: Bool
        switch type {
        case "null":valid=value is NSNull
        case "string":valid=value is String
        case "object":valid=value is [String:Any]
        case "array":valid=value is [Any]
        case "boolean":valid=boolean(value)
        case "integer":
            if let n=value as? NSNumber { valid = !boolean(n) && !["f","d"].contains(String(cString:n.objCType)) }
            else { valid=false }
        default:valid=false
        }
        guard valid else { throw AdvisoryError.invalid }
    }
    private static func time(_ text:String) -> Bool {
        let fractional=ISO8601DateFormatter();fractional.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        return (text.hasSuffix("Z") || text.hasSuffix("+00:00")) && (ISO8601DateFormatter().date(from:text) != nil || fractional.date(from:text) != nil)
    }
    static func digest(_ raw: Any) throws -> String {
        let data=try JSONSerialization.data(withJSONObject:raw,options:[.sortedKeys,.withoutEscapingSlashes])
        let ascii=String(decoding:data,as:UTF8.self).unicodeScalars.map { scalar -> String in
            let v=scalar.value
            if v<128 { return String(scalar) }
            if v<=0xffff { return String(format:"\\u%04x",v) }
            return String(format:"\\u%04x\\u%04x",0xd800+((v-0x10000)>>10),0xdc00+((v-0x10000)&0x3ff))
        }.joined()
        return "sha256:"+SHA256.hash(data:Data(ascii.utf8)).map{String(format:"%02x",$0)}.joined()
    }
    static func decode<T:Decodable>(_ raw: Any, as type:T.Type) throws -> T {
        try JSONDecoder().decode(type,from:JSONSerialization.data(withJSONObject:raw))
    }
    static func object(_ data: Data) throws -> [String:Any] {
        guard data.count<=65536, let raw=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw AdvisoryError.invalid };return raw
    }
    static func scope(_ raw: [String:Any], access: AdvisoryAccess) throws {
        guard raw["instance_id"] as? String==access.forgeInstanceID, raw["project_id"] as? String==access.forgeProjectID,
              raw["repository_id"] as? String==access.repositoryID else { throw AdvisoryError.denied }
    }
    static func capability(_ data: Data, access: AdvisoryAccess) throws -> AdvisoryCapability {
        let raw=try object(data);try validate(raw,kind:"capability");try scope(raw,access:access)
        let cap=try decode(raw,as:AdvisoryCapability.self)
        guard Set(cap.conversation_ids)==Set(access.conversationIDs), try digest(raw["context"]!)==cap.context_revision,
              Set(cap.available_sources.map(\.source_id)).count==cap.available_sources.count else { throw AdvisoryError.invalid }
        return cap
    }
    static func turn(_ raw: Any, access:AdvisoryAccess, conversation:String) throws -> AdvisoryTurnRecord {
        try validate(raw,kind:"turn_record")
        let obj=raw as! [String:Any], request=obj["request"] as! [String:Any], context=obj["context"] as! [String:Any]
        try scope(request,access:access);try scope(context,access:access)
        let t=try decode(obj,as:AdvisoryTurnRecord.self)
        guard access.conversationIDs.contains(conversation), t.request.conversation_id==conversation,
              try digest(request)==t.request_digest, try digest(context)==t.request.context_revision,
              t.context.selected_sources==t.request.selected_sources else { throw AdvisoryError.invalid }
        if let o=t.outcome {
            guard o.execution==t.execution else { throw AdvisoryError.invalid }
            if let output=o.output {
                let texts=[output.summary]+output.alternatives+output.questions+output.suggestions+output.evidence_references
                let rawOutput=(obj["outcome"] as! [String:Any])["output"]!
                guard output.request_digest==t.request_digest, output.advisor_kind==t.request.advisor_kind,
                      try digest(rawOutput)==o.result_digest, texts.allSatisfy(safe),
                      Set(output.evidence_references).isSubset(of:Set(t.context.evidence_references)) else { throw AdvisoryError.invalid }
            }
            if t.status=="COMPLETE" {
                guard o.output != nil, o.execution=="CONFIRMED", o.error_code==nil, o.usage_status=="OBSERVED", let usage=o.usage,
                      usage.input_tokens<=t.provider.input_token_bound, usage.output_tokens<=t.provider.output_token_bound else { throw AdvisoryError.invalid }
            }
        } else if t.status=="COMPLETE" { throw AdvisoryError.invalid }
        return t
    }
    static func safe(_ text:String) -> Bool {
        text.unicodeScalars.allSatisfy { $0.value>=32 || $0.value==10 || $0.value==9 } && !text.contains("<") && !text.contains(">") &&
        text.range(of:#"https?://[^/\s]+:[^/\s]+@|bearer\s+|api[_-]?key\s*[:=]|password\s*[:=]|sk-[A-Za-z0-9]"#,options:[.regularExpression,.caseInsensitive])==nil
    }
    static func observation(_ data:Data, kind:String, access:AdvisoryAccess, conversation:String,
                            expected:AdvisoryRequest?=nil) throws -> AdvisoryObservation {
        let raw=try object(data);try validate(raw,kind:kind)
        let t=try turn(raw["original_turn"]!,access:access,conversation:conversation)
        let revision=raw["current_revision"] as! Int
        guard revision>=t.request.expected_revision+1, expected==nil || expected==t.request else { throw AdvisoryError.invalid }
        return AdvisoryObservation(turn:t,currentRevision:revision)
    }
    static func history(_ data:Data, access:AdvisoryAccess, conversation:String) throws -> AdvisoryHistory {
        let raw=try object(data);try validate(raw,kind:"history");try scope(raw["scope"] as! [String:Any],access:access)
        let h=try decode(raw,as:AdvisoryHistory.self)
        guard h.conversation_id==conversation, Set(h.turns.map{$0.request.turn_id}).count==h.turns.count else { throw AdvisoryError.invalid }
        for rawTurn in raw["turns"] as! [Any] { _=try turn(rawTurn,access:access,conversation:conversation) }
        return h
    }
}
