import XCTest
import Foundation
import SwiftUI
import AppKit
@testable import WorkspaceClient

@MainActor final class GenesisViewInteractionTests:XCTestCase {
    func elements(_ node:any NSAccessibilityProtocol,depth:Int=0)->[any NSAccessibilityProtocol] {
        guard depth<20 else {return []}
        return [node]+(node.accessibilityChildren() ?? []).flatMap{child in
            guard let next=child as? any NSAccessibilityProtocol else {return [any NSAccessibilityProtocol]()}
            return elements(next,depth:depth+1)
        }
    }
    func find(_ host:NSHostingView<some View>,_ id:String)->(any NSAccessibilityProtocol)? {elements(host.window ?? host).first{$0.accessibilityIdentifier()==id}}
    func testActualHostedDocumentControlOpensAuthorizedOriginalAndReturnsToOpener()async throws {
        _ = NSApplication.shared
        let peer=try GenesisFixture();let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let state=GenesisState(root:root,transport:peer);let c=peer.connection
        await state.load(peer.concept,source:peer.source,current:{c});await state.prepare(peer.concept,source:peer.source,target:"local",current:{c})
        state.updateReason("Synthetic explicit source UI reason")
        let view=GenesisView(state:state,concept:peer.concept,source:peer.source,dirty:false,current:{c},reveal:{_ in})
        let host=NSHostingView(rootView:view.accessibilityElement(children:.contain).accessibilityIdentifier("genesis-test-root"));let window=NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:1000),styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.contentView=host;window.orderFront(nil)
        defer{window.close();state.conceal()}
        host.frame=NSRect(x:0,y:0,width:760,height:1000);host.layoutSubtreeIfNeeded()
        for _ in 0..<20 {if state.result != nil && !state.busy {break};try await Task.sleep(for:.milliseconds(20))}
        try await Task.sleep(for:.milliseconds(250));host.layoutSubtreeIfNeeded();print("AXTREE",elements(window).map{String(describing:type(of:$0))+":"+($0.accessibilityIdentifier() ?? "nil")});let disclosure=try XCTUnwrap(find(host,"genesis-documents"));XCTAssertTrue(disclosure.accessibilityPerformPress())
        host.layoutSubtreeIfNeeded();await Task.yield()
        let path=try XCTUnwrap(state.result?.result.plan.documents.files.first?.path)
        let opener=try XCTUnwrap(find(host,"genesis-document-"+path));XCTAssertTrue(opener.accessibilityPerformPress())
        for _ in 0..<40 {if state.expandedDocument==path {break};try await Task.sleep(for:.milliseconds(20))}
        XCTAssertEqual(state.expandedDocument,path);host.layoutSubtreeIfNeeded();await Task.yield()
        let close=try XCTUnwrap(find(host,"genesis-detail-"+path));XCTAssertTrue(close.accessibilityPerformPress())
        for _ in 0..<40 {if state.expandedDocument.isEmpty {break};try await Task.sleep(for:.milliseconds(20))}
        XCTAssertEqual(state.expandedDocument,"")
        let count=await peer.count();XCTAssertEqual(count,1)
    }
}
