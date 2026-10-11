import XCTest
@testable import WorkspaceClient

final class CanonicalJSONTests: XCTestCase {
    private func fixture() throws -> [String:Any] {
        let url=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/canonical-producer-2.12.1.json")
        return try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
    }
    func testPinnedProducerBytesAndDigestsForBothContracts() throws {
        for v in try fixture()["vectors"] as! [[String:Any]] {
            XCTAssertEqual(String(decoding:try CanonicalJSON.data(v["value"]!,ascii:true),as:UTF8.self),v["ascii"] as? String)
            XCTAssertEqual(String(decoding:try CanonicalJSON.data(v["value"]!,ascii:false),as:UTF8.self),v["utf8"] as? String)
            XCTAssertEqual(try AdvisoryWire.digest(v["value"]!),v["ascii_digest"] as? String)
            XCTAssertEqual(try AdvisoryWire.digest(v["value"]!,ascii:false),v["utf8_digest"] as? String)
        }
    }
    func testInsertionOrderAndArrayOrderRemainDistinct() throws {
        let first=NSMutableDictionary(), second=NSMutableDictionary()
        for key in ["a2","a10","A","a","a01"] { first[key]=key }
        for key in ["a01","a","A","a10","a2"] { second[key]=key }
        XCTAssertEqual(try CanonicalJSON.data(first,ascii:true),try CanonicalJSON.data(second,ascii:true))
        XCTAssertNotEqual(try AdvisoryWire.digest([first,second,1]),try AdvisoryWire.digest([first,1,second]))
    }
    func testActualPreservedCapabilityAndTampering() throws {
        let raw=try fixture()["capability"] as! [String:Any]
        let access=AdvisoryAccess(endpoint:"http://127.0.0.1:4000/",workspaceInstanceID:"workspace-test",workspaceProjectID:"ws-project",
            actorID:"synthetic-owner",forgeInstanceID:raw["instance_id"] as! String,forgeProjectID:raw["project_id"] as! String,
            repositoryID:raw["repository_id"] as! String,conversationIDs:raw["conversation_ids"] as! [String],token:String(repeating:"a",count:43))
        let data=try JSONSerialization.data(withJSONObject:raw)
        XCTAssertEqual(try MissionConceptWire.capability(data,access:access).context_revision,raw["context_revision"] as? String)
        var altered=raw;var context=raw["context"] as! [String:Any];context["dataset_generation"]=1;altered["context"]=context
        XCTAssertThrowsError(try MissionConceptWire.capability(JSONSerialization.data(withJSONObject:altered),access:access))
        var foreign=raw;foreign["instance_id"]="foreign"
        XCTAssertThrowsError(try MissionConceptWire.capability(JSONSerialization.data(withJSONObject:foreign),access:access))
    }
    func testSupportedTypesEscapingAndUnsupportedValues() throws {
        let text="\u{0000}\u{0001}\u{0008}\t\n\u{000c}\r\"\\/\u{007f}é😀"
        XCTAssertEqual(String(decoding:try CanonicalJSON.data(text,ascii:true),as:UTF8.self),
            "\"\\u0000\\u0001\\b\\t\\n\\f\\r\\\"\\\\/\\u007fé😀\"".replacingOccurrences(of:"é😀",with:"\\u00e9\\ud83d\\ude00"))
        XCTAssertEqual(String(decoding:try CanonicalJSON.data([true,false,NSNull(),-1,0],ascii:false),as:UTF8.self),"[true,false,null,-1,0]")
        for invalid:Any in [Date(),NSNumber(value:1.25),NSNumber(value:Double.nan),NSNumber(value:Double.infinity),NSDictionary(object:1,forKey:NSNumber(value:2))] {
            XCTAssertThrowsError(try CanonicalJSON.data(invalid,ascii:true))
        }
    }
}
