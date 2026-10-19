import XCTest
import Foundation
import SwiftUI
import AppKit
@testable import WorkspaceClient

@MainActor private final class GenesisViewObservations {
    var anchors:[String]=[]
}
@MainActor final class GenesisViewLifecycleTests:XCTestCase {
    private func waitUntil(_ seconds:Double=2,_ condition:()->Bool) async throws {
        let deadline=Date().addingTimeInterval(seconds)
        while !condition() && Date()<deadline {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertTrue(condition(),"Actual hosted lifecycle did not reach its bounded expected observation")
    }
    func testHostedOriginalDocumentRevealsAgainAfterRealMonitorFailureAndRecovery()async throws {
        _=NSApplication.shared
        let peer=try GenesisFixture();let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let state=GenesisState(root:root,transport:peer);let c=peer.connection
        await state.load(peer.concept,source:peer.source,current:{c});await state.prepare(peer.concept,source:peer.source,target:"local",current:{c})
        let path=try XCTUnwrap(state.result?.result.plan.documents.files.first?.path)
        await state.chooseDocument(path,concept:peer.concept,source:peer.source,current:{c});state.updateReason("Original source-only hosted lifecycle reason")
        let observations=GenesisViewObservations()
        let view=ScrollViewReader {proxy in
            ScrollView {GenesisView(state:state,concept:peer.concept,source:peer.source,dirty:false,current:{c},reveal:{id in observations.anchors.append(id);proxy.scrollTo(id,anchor:.top)})}
        }.frame(width:760,height:780)
        let host=NSHostingView(rootView:view);let window=NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:780),styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.contentView=host
        defer{window.close();state.conceal()}
        host.frame=NSRect(x:0,y:0,width:760,height:780);host.layoutSubtreeIfNeeded();_=host.fittingSize
        try await waitUntil {observations.anchors==["genesis-detail-"+path]}
        XCTAssertTrue(state.documentsVisible);XCTAssertEqual(state.expandedDocument,path)
        await peer.setUnavailable(true);try await waitUntil(4.5) {state.result==nil}
        XCTAssertFalse(state.documentsVisible);XCTAssertEqual(state.reason,"");XCTAssertEqual(observations.anchors.count,1)
        await peer.setUnavailable(false)
        try await waitUntil(4.5) {observations.anchors==["genesis-detail-"+path,"genesis-detail-"+path]}
        XCTAssertNotNil(state.result);XCTAssertEqual(state.expandedDocument,path);XCTAssertEqual(state.reason,"Original source-only hosted lifecycle reason")
        host.layoutSubtreeIfNeeded();XCTAssertEqual(host.frame.width,760)
        let count=await peer.count();XCTAssertEqual(count,1,"Hosting and authorized restoration must never create another producer effect")
    }
    func testHostedInspectSectionsKeepOriginalDecisionQuestionsAndSourceWithoutEffects()async throws {
        for scenario in ["APPROVE_EFFECT","REQUEST_CHANGES","blocked"] {
            let peer=try GenesisFixture();let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)};let c=peer.connection;let state=GenesisState(root:root,transport:peer)
            await state.load(peer.concept,source:peer.source,current:{c});await state.prepare(peer.concept,source:peer.source,target:"local",current:{c})
            if scenario=="blocked" {await peer.presentationVariant("blocked");await state.load(peer.concept,source:peer.source,current:{c})}
            else {
                let selection=try XCTUnwrap(state.result?.selection_digest)
                await state.decide(peer.concept,source:peer.source,decision:scenario,reason:"Source-only explicit decision presentation",expectedSelection:selection,current:{c})
            }
            for key in ["history","steps","questions","decisions","source"] {state.setSection(key,true)}
            let path=try XCTUnwrap(state.result?.result.plan.documents.files.first?.path);await state.chooseDocument(path,concept:peer.concept,source:peer.source,current:{c})
            let view=GenesisView(state:state,concept:peer.concept,source:peer.source,dirty:scenario=="blocked",current:{c},reveal:{_ in}).environment(\.locale,Locale(identifier:"nl"))
            let host=NSHostingView(rootView:view);defer{withExtendedLifetime(host){}}
            host.frame=NSRect(x:0,y:0,width:520,height:780);host.layoutSubtreeIfNeeded();XCTAssertGreaterThan(host.fittingSize.height,0);XCTAssertEqual(host.frame.width,520)
            try await waitUntil { !state.busy && state.result != nil && state.sections.count==5 }
            XCTAssertEqual(state.sections,Set(["history","steps","questions","decisions","source"]));state.conceal();await state.load(peer.concept,source:peer.source,current:{c});XCTAssertEqual(state.sections.count,5)
            if scenario=="blocked" {XCTAssertFalse(try XCTUnwrap(state.result).can_approve!);XCTAssertFalse(try XCTUnwrap(state.result).result.plan.blocking_open_points.isEmpty)}
            else {XCTAssertEqual(state.result?.result.effect_history.last?.decision,scenario)}
            let count=await peer.count();XCTAssertEqual(count,scenario=="blocked" ? 1:2);state.conceal()
        }
    }
    func testHostedMissingRoleAndNoOwnerTargetsRemainReadOnlyAndUnderstandable()async throws {
        for scenario in ["missingArchitecture","noTargets"] {
            let peer=try GenesisFixture();await peer.presentationVariant(scenario);let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)};let c=peer.connection;let state=GenesisState(root:root,transport:peer)
            await state.load(peer.concept,source:peer.source,current:{c})
            if scenario=="missingArchitecture" {XCTAssertEqual(state.access?.content.missingRoles,["ARCHITECTURE"])}
            else {XCTAssertTrue(try XCTUnwrap(state.access).targets.isEmpty);XCTAssertFalse(try XCTUnwrap(state.access).can_plan)}
            let host=NSHostingView(rootView:GenesisView(state:state,concept:peer.concept,source:peer.source,dirty:false,current:{c},reveal:{_ in}));host.frame=NSRect(x:0,y:0,width:520,height:780);host.layoutSubtreeIfNeeded();XCTAssertGreaterThan(host.fittingSize.height,0)
            XCTAssertNil(state.result);let count=await peer.count();XCTAssertEqual(count,0);state.conceal()
        }
    }

}
