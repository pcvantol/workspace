import XCTest
import SwiftUI
import AppKit
@testable import WorkspaceClient

@MainActor final class ProposalContentViewTests:XCTestCase {
    func render<V:View>(_ view:V,width:Double,language:String,scheme:ColorScheme) {
        let host=NSHostingView(rootView:view.environment(\.locale,Locale(identifier:language)).environment(\.colorScheme,scheme))
        host.frame=NSRect(x:0,y:0,width:width,height:1000);host.layoutSubtreeIfNeeded();XCTAssertGreaterThan(host.fittingSize.height,0)
        let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds);XCTAssertNotNil(bitmap)
        if let bitmap {host.cacheDisplay(in:host.bounds,to:bitmap);XCTAssertGreaterThan(bitmap.pixelsWide,0)}
    }
    func testFiveLanguagesNarrowWideThemesAndDistinctDecisionReadStates()async throws {
        for (key,values) in ProposalContentCopy.values {
            XCTAssertEqual(values.count,5)
            for language in ProposalContentCopy.languages {XCTAssertNotEqual(ProposalContentCopy.text(key,language),key)}
        }
        XCTAssertEqual(ProposalContentCopy.text("title","unknown"),ProposalContentCopy.text("title","en"));XCTAssertEqual(ProposalContentCopy.text("absent","nl"),"absent")
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let peer=try ContentFixture();let state=ProposalContentState(transport:peer,root:root);let c=CompareFixture.connection;let concept=CompareFixture.concept
        await state.load(peer.source,concept:concept,current:{c});state.stage(role:"BUSINESS",choice:"REQUEST_CHANGES",reason:"Synthetic reason",acknowledged:true,concept:concept);await state.confirm(peer.source,concept:concept,current:{c})
        for language in ProposalContentCopy.languages {
            for width in [520.0,1150.0] {
                for scheme in [ColorScheme.light,.dark] {render(ProposalContentView(state:state,concept:concept,source:peer.source,dirty:false,current:{c},discuss:{},returnFocusRequest:0,reveal:{}),width:width,language:language,scheme:scheme)}
            }
        }
        peer.permissions=["READ"];peer.roles=[];await state.load(peer.source,concept:concept,current:{c});render(ProposalContentView(state:state,concept:concept,source:peer.source,dirty:false,current:{c},discuss:{},returnFocusRequest:1,reveal:{}),width:520,language:"nl",scheme:.dark)
        for phase in ["choose","access","conflict","unavailable","invalid","unsupported","capacity"] {
            state.result=nil;state.phase=phase;state.busy=phase=="unavailable"
            render(ProposalContentView(state:state,concept:concept,source:peer.source,dirty:true,current:{c},discuss:{},returnFocusRequest:0,reveal:{}),width:520,language:"en",scheme:.light)
        }
        let command=ProposalContentCommand(operation_id:CompareFixture.second,source_operation_id:peer.source.operation_id,expected_concept_revision:3,selection_digest:String(repeating:"1",count:64),role:"ARCHITECTURE",decision:"APPROVE_CONTENT",reason:"Explicit synthetic decision, not a user approval",acknowledged_open_points:peer.source.source_product.open_questions)
        for language in ProposalContentCopy.languages {render(ProposalContentConfirmation(source:peer.source,currentRevision:3,command:command,language:language,confirm:{},cancel:{}),width:520,language:language,scheme:.dark)}
        state.conceal()
    }
}
