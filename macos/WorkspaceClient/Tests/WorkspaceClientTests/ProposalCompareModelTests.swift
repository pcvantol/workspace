import XCTest
@testable import WorkspaceClient

final class ProposalCompareModelTests:XCTestCase {
    func testActualFourStatusesExactPathIdentityAndQuestionDisposition()throws {
        let a=try CompareFixture.result(CompareFixture.first,documents:["README.md":"old\n","same":"é\n","old-name":"same bytes"],questions:["Still?","No longer included?"])
        let b=try CompareFixture.result(CompareFixture.second,revision:2,documents:["README.md":"new\n","same":"é\n","new-name":"same bytes"],questions:["Still?","New?"])
        let model=try ProposalCompareModel.make(a,b);let map=Dictionary(uniqueKeysWithValues:model.documents.map{($0.path,$0.status)})
        XCTAssertEqual(map["README.md"],"changed");XCTAssertEqual(map["same"],"unchanged");XCTAssertEqual(map["old-name"],"removed");XCTAssertEqual(map["new-name"],"added")
        XCTAssertEqual(model.questions.map(\.status),["present","omitted","newQuestion"])
        XCTAssertEqual(model.fields.first?.before,"Original 1");XCTAssertEqual(model.fields.first?.after,"Original 2")
        XCTAssertTrue(model.fields.first!.changed);XCTAssertEqual(model.before.current_revision,3)
        XCTAssertEqual(model.documents.first(where:{$0.path=="same"})?.group,"otherDocs")
        for (path,group) in [("docs/product/VISION.md","productDocs"),("docs/architecture/A.md","architectureDocs"),("docs/roadmap/B.md","roadmapDocs"),("BOOTSTRAP.md","workingDocs"),("docs/engineering/A.md","workingDocs")] {XCTAssertEqual(ProposalCompareModel.Document(path:path,before:nil,after:nil).group,group)}
    }
    func testUTF8NormalizationWhitespaceCRLFAreNotSilentlyIdentical()throws {
        for (old,new) in [("é\n","e\u{301}\n"),("a\r\n","a\n"),("a b\n","a  b\n"),("tab\t\n","tab \n"),("last","last\n")] {
            let document=ProposalCompareModel.Document(path:"README.md",before:CompareFixture.artifact("README.md",old),after:CompareFixture.artifact("README.md",new))
            XCTAssertEqual(document.status,"changed");let diff=ProposalCompareModel.difference(document);XCTAssertFalse(diff.rows.isEmpty);XCTAssertTrue(diff.complete)
        }
        XCTAssertEqual(ProposalCompareModel.visible(" \t\r\n"),"·⇥␍␊\n")
        XCTAssertEqual(ProposalCompareModel.lines("a\r\nb\nc"),["a\r\n","b\n","c"])
        let same=try CompareFixture.result(CompareFixture.first);let identical=try ProposalCompareModel.make(same,CompareFixture.result(CompareFixture.second))
        XCTAssertEqual(identical.changedDocuments,0)
    }
    func testLinearContextDiffBoundsAndAllOriginalPagesRemainExact()throws {
        let old="same\nold\ncontext\nend\n",new="same\nnew\ncontext\nnew ending\n"
        let d=ProposalCompareModel.Document(path:"README.md",before:CompareFixture.artifact("README.md",old),after:CompareFixture.artifact("README.md",new));let diff=ProposalCompareModel.difference(d)
        XCTAssertTrue(diff.rows.contains(where:{$0.sign==" " && $0.text=="context\n"}));XCTAssertTrue(diff.rows.contains(where:{$0.sign=="−"}));XCTAssertTrue(diff.rows.contains(where:{$0.sign=="+"}))
        let big=String(repeating:"x\n",count:9000);let bounded=ProposalCompareModel.difference(.init(path:"README.md",before:CompareFixture.artifact("README.md",String(repeating:"\n",count:9000)),after:CompareFixture.artifact("README.md",big)))
        XCTAssertFalse(bounded.complete);XCTAssertEqual(bounded.rows.count,8192)
        let unicode=String(repeating:"🌱e\u{301}\r\n",count:3000);let pages=ProposalCompareModel.pages(unicode);XCTAssertGreaterThan(pages.count,1);XCTAssertEqual(Data(pages.joined().utf8),Data(unicode.utf8));XCTAssertEqual(ProposalCompareModel.pages(""),[""])
        let added=ProposalCompareModel.difference(.init(path:"new",before:nil,after:CompareFixture.artifact("new","new")));XCTAssertEqual(added.rows.map(\.sign),["+"])
        let removed=ProposalCompareModel.difference(.init(path:"old",before:CompareFixture.artifact("old","old"),after:nil));XCTAssertEqual(removed.rows.map(\.sign),["−"])
    }
    func testFailClosedScopeUnsupportedProfileDuplicateAndOversizedResults()throws {
        let a=try CompareFixture.result(CompareFixture.first)
        for key in ["actor_id","context_id","concept_id","binding_id","producer_source"] {var object=CompareFixture.object(CompareFixture.second);object[key]="other";XCTAssertThrowsError(try ProposalCompareModel.make(a,CompareFixture.decode(object)))}
        XCTAssertThrowsError(try ProposalCompareModel.make(a,CompareFixture.result(CompareFixture.second,profile:"future-profile/2")))
        var object=CompareFixture.object(CompareFixture.second);var proposal=object["proposal"] as! [String:Any];var result=proposal["result"] as! [String:Any];var artifacts=result["artifacts"] as! [[String:Any]];artifacts.append(artifacts[0]);result["artifacts"]=artifacts;proposal["result"]=result;object["proposal"]=proposal;XCTAssertThrowsError(try ProposalCompareModel.make(a,CompareFixture.decode(object)))
        XCTAssertThrowsError(try ProposalCompareModel.make(a,CompareFixture.result(CompareFixture.second,documents:["README.md":String(repeating:"x",count:131073)])))
        let mode=ProposalCompareModel.Document(path:"x",before:CompareFixture.artifact("x","same"),after:CompareFixture.artifact("x","same",mode:493));XCTAssertEqual(mode.status,"changed");XCTAssertTrue(ProposalCompareModel.difference(mode).rows.isEmpty)
    }
}
