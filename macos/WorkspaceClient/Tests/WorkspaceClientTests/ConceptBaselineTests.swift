import XCTest
import SwiftUI
@testable import WorkspaceClient

final class ConceptBaselineTests:XCTestCase {
    func concept(notes:String="Saved description",lifecycle:String="ACTIVE") -> ProjectConcept {
        .init(id:String(repeating:"a",count:32),actor_id:"alice",context_id:"context",title:"Saved idea",notes:notes,revision:1,created_at:"2026-10-13T12:00:00Z",updated_at:"2026-10-13T12:00:00Z",state:"CONCEPT_NOT_CONFIGURED",lifecycle:lifecycle)
    }
    func testSavedSourceNeverUsesUnsavedOrArchivedContent() throws {
        let saved=concept();let source=try ConceptBaselineDraftSource.capture(saved,choice:nil,dirty:false)
        XCTAssertEqual(source.originalNotes,saved.notes);XCTAssertEqual(source.revision,1);XCTAssertNil(source.chosenPurpose)
        XCTAssertThrowsError(try ConceptBaselineDraftSource.capture(saved,choice:nil,dirty:true))
        XCTAssertThrowsError(try ConceptBaselineDraftSource.capture(concept(lifecycle:"ARCHIVED"),choice:nil,dirty:false))
    }
    func testLongPurposeChoiceDoesNotTruncateNotes() throws {
        let saved=concept(notes:String(repeating:"n",count:4097))
        XCTAssertThrowsError(try ConceptBaselineDraftSource.capture(saved,choice:nil,dirty:false))
        let source=try ConceptBaselineDraftSource.capture(saved,choice:"Explicit shorter purpose",dirty:false)
        XCTAssertEqual(source.originalNotes,saved.notes);XCTAssertEqual(source.chosenPurpose,"Explicit shorter purpose")
        XCTAssertThrowsError(try ConceptBaselineDraftSource.capture(saved,choice:"",dirty:false))
        XCTAssertThrowsError(try ConceptBaselineDraftSource.capture(saved,choice:String(repeating:"n",count:4097),dirty:false))
    }
    @MainActor func testAllFiveLabelsAndSafeDraftReviewRender() {
        for language in ConceptBaselineCopy.languages {
            for values in ConceptBaselineCopy.values.values {XCTAssertEqual(values.count,5);XCTAssertFalse(values[ConceptBaselineCopy.languages.firstIndex(of:language)!].isEmpty)}
            let host=NSHostingView(rootView:ConceptBaselineDraftView(concept:concept(),dirty:false).environment(\.locale,Locale(identifier:language)))
            host.frame=NSRect(x:0,y:0,width:560,height:780);host.layoutSubtreeIfNeeded();_=host.fittingSize
        }
        XCTAssertTrue(ConceptBaselineCopy.text("english","nl").contains("Engels"))
        XCTAssertEqual(ConceptBaselineCopy.text("make","unknown"),ConceptBaselineCopy.text("make","en"))
    }
    @MainActor func testPreflightShowsExactSavedSourceAndHonestLongChoiceAtBothWidths() {
        for language in ConceptBaselineCopy.languages {
            for notes in ["", "Verbatim saved purpose",String(repeating:"n",count:4097)] {
                for width in [520.0,900.0] {
                    let host=NSHostingView(rootView:ConceptBaselineDraftView(concept:concept(notes:notes),dirty:false,onPrepare:{_ in},reviewing:true).environment(\.locale,Locale(identifier:language)))
                    host.frame=NSRect(x:0,y:0,width:width,height:780);host.layoutSubtreeIfNeeded();_=host.fittingSize
                    XCTAssertEqual(host.frame.width,width)
                }
            }
        }
        for saved in [concept(),concept(lifecycle:"ARCHIVED")] {
            let host=NSHostingView(rootView:ConceptBaselineDraftView(concept:saved,dirty:true,reviewing:true))
            host.frame=NSRect(x:0,y:0,width:520,height:780);host.layoutSubtreeIfNeeded();_=host.fittingSize
        }
    }

}
