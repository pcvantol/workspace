import XCTest
import SwiftUI
@testable import WorkspaceClient

final class ConceptChatTests:XCTestCase {
    func concept(_ lifecycle:String="ACTIVE")->ProjectConcept {
        .init(id:String(repeating:"a",count:32),actor_id:"alice",context_id:"context",title:"Saved idea",notes:"Original user text",revision:1,created_at:"2026-10-14T06:00:00Z",updated_at:"2026-10-14T06:00:00Z",state:"CONCEPT_NOT_CONFIGURED",lifecycle:lifecycle)
    }
    func testCopyAndMessageBoundaries() {
        for language in ConceptChatCopy.languages {
            for (key,values) in ConceptChatCopy.values {
                XCTAssertEqual(values.count,5)
                XCTAssertFalse(ConceptChatCopy.text(key,language).isEmpty)
            }
        }
        XCTAssertEqual(ConceptChatCopy.text("chat","unknown"),ConceptChatCopy.text("chat","en"))
        for text in ["", " \n",String(repeating:"x",count:4097),"bad\u{0}"] {XCTAssertFalse(ConceptChatCopy.validMessage(text))}
        for text in ["Eigen vraag 日本語",String(repeating:"🌱",count:4096),"literal <script>not code</script>"] {XCTAssertTrue(ConceptChatCopy.validMessage(text))}
    }
    @MainActor func testOwningFiveLanguageResponsiveViewsAndSafeData() {
        let access=ConceptChatAccess(profile:"Explicit test profile — synthetic fixture",recipient:"Configured test service",limits:"Finite fixture limit",maySubmit:true)
        let turn=ConceptChatTurn(id:"test-turn",role:"BUSINESS",message:"Who is this for?",answer:"Synthetic example only; not live advice.",sourceRevision:1)
        let current=ConceptChatProposal(reference:"test-result",sourceRevision:1,changes:[.init(field:"users",before:"",after:"Volunteers",reason:"User-declared intention")])
        let stale=ConceptChatProposal(reference:"older-result",sourceRevision:0,changes:current.changes)
        for language in ConceptChatCopy.languages {
            for width in [520.0,1100.0] {
                for scheme in [ColorScheme.light,.dark] {
                    for proposal in [Optional<ConceptChatProposal>.none,current,stale] {
                        let view=ConceptChatView(concept:concept(),dirty:false,access:access,turns:[turn],proposal:proposal,onSend:{_,_ in},onAccept:{_ in},message:"An explicit user question",reviewing:true)
                        let host=NSHostingView(rootView:view.environment(\.locale,Locale(identifier:language)).environment(\.colorScheme,scheme))
                        host.frame=NSRect(x:0,y:0,width:width,height:850);host.layoutSubtreeIfNeeded();_=host.fittingSize
                        XCTAssertEqual(host.frame.width,width)
                    }
                }
            }
        }
        for lifecycle in ["ACTIVE","ARCHIVED"] {
            let host=NSHostingView(rootView:ConceptChatView(concept:concept(lifecycle),dirty:true))
            host.frame=NSRect(x:0,y:0,width:520,height:800);host.layoutSubtreeIfNeeded();_=host.fittingSize
        }
        XCTAssertEqual(current.changes[0].id,"users")
    }
}
