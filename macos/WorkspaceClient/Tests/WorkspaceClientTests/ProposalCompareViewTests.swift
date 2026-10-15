import XCTest
import SwiftUI
import AppKit
@testable import WorkspaceClient

@MainActor final class ProposalCompareViewTests:XCTestCase {
    func testFiveLanguageCopyCoversEveryStateWithoutApprovalClaim() {
        for (key,values) in ProposalCompareCopy.values {
            XCTAssertEqual(values.count,5)
            for language in ["en","nl","de","fr","es"] {XCTAssertFalse(ProposalCompareCopy.text(key,language).isEmpty)}
        }
        XCTAssertEqual(ProposalCompareCopy.text("before","en"),"First selection")
        XCTAssertEqual(ProposalCompareCopy.text("before","unknown"),ProposalCompareCopy.text("before","en"))
        XCTAssertEqual(ProposalCompareCopy.text("otherDocs","nl"),ConceptBaselineCopy.text("otherDocs","nl"))
        XCTAssertEqual(ProposalCompareCopy.text("absent-key","nl"),"absent-key")
    }
    func render<V:View>(_ view:V,width:Double,language:String="nl",scheme:ColorScheme = .dark) {
        let host=NSHostingView(rootView:view.environment(\.locale,Locale(identifier:language)).environment(\.colorScheme,scheme))
        host.frame=NSRect(x:0,y:0,width:width,height:900);host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height,0)
        let rect=host.bounds
        if let bitmap=host.bitmapImageRepForCachingDisplay(in:rect) {host.cacheDisplay(in:rect,to:bitmap);XCTAssertGreaterThan(bitmap.pixelsWide,0)}
        else {XCTFail("Native view could not produce a bounded render")}
    }
    func testNamedFiveLanguageNarrowWideThemesAndHistoricalSummaryStates()throws {
        let peer=try ComparePeer();let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)};let state=ProposalCompareState(transport:peer,root:root);let c=CompareFixture.connection
        state.history=[.init(operation_id:CompareFixture.first,source_revision:1),.init(operation_id:CompareFixture.second,source_revision:2)];state.choice = .init(before:CompareFixture.first,after:CompareFixture.second)
        let a=try CompareFixture.result(CompareFixture.first,documents:["README.md":"literal <script>not executable</script>\n","docs/product/VISION.md":"old","docs/architecture/A.md":"same","docs/roadmap/A.md":"same","AGENTS.md":"same"])
        let b=try CompareFixture.result(CompareFixture.second,revision:2,documents:["README.md":"literal <a href='https://invalid.example'>text</a>\n","docs/product/VISION.md":"new","docs/architecture/A.md":"same","docs/roadmap/A.md":"same","AGENTS.md":"same"],questions:["New question?"])
        let model=try ProposalCompareModel.make(a,b)
        for language in ["en","nl","de","fr","es"] {
            for width in [520.0,1150.0] {
                for scheme in [ColorScheme.light,.dark] {
                    state.comparison=model;state.phase="comparable"
                    render(ProposalCompareView(state:state,concept:CompareFixture.concept,current:{c},differencesOnly:false),width:width,language:language,scheme:scheme)
                }
            }
        }
        for phase in ["idle","loading","none","single","identical","denied","invalid","incompatible","unavailable","partial","sourceChanged","chooseDifferent"] {
            state.comparison=nil;state.phase=phase;state.busy=phase=="loading";state.partialHistory=phase=="partial";render(ProposalCompareView(state:state,concept:CompareFixture.concept,current:{c}),width:520)
        }
        XCTAssertEqual(peer.posts,0);state.conceal()
    }
    func testDocumentBoundedDiffOriginalTextAbsentSidesAndMetadataOnlyViews()throws {
        let old=CompareFixture.artifact("docs/product/VISION.md",String(repeating:"old é\r\n",count:130)),new=CompareFixture.artifact("docs/product/VISION.md",String(repeating:"new e\u{301}\n",count:130))
        let document=ProposalCompareModel.Document(path:old.path,before:old,after:new);let diff=ProposalCompareModel.difference(document)
        for language in ["en","nl","de","fr","es"] {
            for page in [0,1] {render(ProposalCompareDocumentView(document:document,language:language,expanded:true,difference:diff,page:page,invisible:true),width:520,language:language)}
        }
        render(ProposalCompareDocumentView(document:document,language:"nl",expanded:false),width:1100)
        render(ProposalCompareDocumentView(document:document,language:"nl",expanded:true,difference:.init(rows:diff.rows,complete:false)),width:520)
        render(ProposalCompareDocumentView(document:document,language:"nl",expanded:true,difference:nil),width:520)
        let mode=ProposalCompareModel.Document(path:"mode",before:CompareFixture.artifact("mode","identical"),after:CompareFixture.artifact("mode","identical",mode:493));render(ProposalCompareDocumentView(document:mode,language:"nl",expanded:true,difference:ProposalCompareModel.difference(mode)),width:520)
        render(ProposalCompareDocumentView(document:.init(path:"new",before:nil,after:new),language:"nl",expanded:true,difference:.init(rows:[],complete:true)),width:520)
        render(ProposalCompareOriginalView(value:CompareFixture.artifact("large",String(repeating:"🌱",count:10000)),side:"Before",language:"nl",page:1),width:520)
        render(ProposalCompareOriginalView(value:nil,side:"After",language:"nl"),width:520)
    }
}
