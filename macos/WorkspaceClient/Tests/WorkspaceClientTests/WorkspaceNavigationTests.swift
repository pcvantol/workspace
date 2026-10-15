import XCTest
import SwiftUI
@testable import WorkspaceClient

final class WorkspaceNavigationTests: XCTestCase {
    @MainActor func testFiniteViewportAndStablePeerRoutesAcrossWindowSizes() async throws {
        for invalid: CGFloat in [-1, 0, .nan, .infinity, -.infinity] {
            XCTAssertEqual(WorkspaceDestination.finite(invalid,fallback:560),560)
        }
        XCTAssertEqual(WorkspaceDestination.finite(760,fallback:560),760)
        for language in ["en","nl","de","fr","es"] {
            let destinations=WorkspaceDestination.items(language:language)
            XCTAssertEqual(Set(destinations.map(\.id)),[0,1,2,3,4,5,6,7,8])
            XCTAssertEqual(destinations.first?.id,5)
            XCTAssertTrue(destinations.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
            var selected=4
            let binding=Binding(get:{selected},set:{selected=$0})
            for size in [NSSize(width:560,height:520),NSSize(width:760,height:780),NSSize(width:1180,height:780)] {
                for destination in destinations {
                    selected=destination.id
                    let shell=WorkspaceNavigationShell(selected:binding,language:language) { id in
                        Text("Selected destination \(id)").accessibilityIdentifier("selected-destination-\(id)")
                    }
                    let host=NSHostingView(rootView:shell)
                    let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
                    window.isReleasedWhenClosed=false
                    window.contentView=host;host.frame=NSRect(origin:.zero,size:size)
                    host.layoutSubtreeIfNeeded();await Task.yield();host.layoutSubtreeIfNeeded()
                    XCTAssertGreaterThan(host.bounds.width,0);XCTAssertGreaterThan(host.bounds.height,0)
                    func assertFinite(_ view:NSView) {
                        XCTAssertTrue(view.frame.origin.x.isFinite && view.frame.origin.y.isFinite)
                        XCTAssertTrue(view.frame.width.isFinite && view.frame.height.isFinite)
                        XCTAssertGreaterThanOrEqual(view.frame.width,0);XCTAssertGreaterThanOrEqual(view.frame.height,0)
                        for child in view.subviews {assertFinite(child)}
                    }
                    assertFinite(host)
                    XCTAssertEqual(selected,destination.id)
                    window.contentView=nil;window.close()
                }
            }
        }
    }
}

private struct NavigationNoCredentials: CredentialStore {
    func binding() throws -> ServerBinding? { nil }
    func token() throws -> String? { nil }
    func save(binding: ServerBinding, token: String) throws {}
    func forget() throws {}
}
private struct NavigationNoGrant: DraftGrantStore {
    func load() throws -> DraftAccess? { nil }
    func save(_ access: DraftAccess) throws {}
    func forget() throws {}
}
extension WorkspaceNavigationTests {
    @MainActor func testRealConceptAndMissionPanesStayInsideWindowViewport() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let client=ClientState(keychain:NavigationNoCredentials())
        let state=ProjectConceptState(root:root)
        state.title=String(repeating:"Idea ",count:24)
        state.notes=String(repeating:"Nederlands · English · Deutsch · français · español 🌱\n",count:160)
        for language in ["en","nl","de","fr","es"] {
            for size in [NSSize(width:560,height:720),NSSize(width:760,height:780),NSSize(width:1180,height:780)] {
                for destination in [4,5] {
                    let shell=WorkspaceNavigationShell(selected:.constant(destination),language:language) { id in
                        if id==5 {
                            ProjectConceptView(state:state,client:client,grants:NavigationNoGrant())
                                .environment(\.nativeTabCommandsActive,true)
                        } else {
                            MissionWorkspaceView(observation:nil,canRefine:false,canApprove:false,onRefine:{_,_,_ in},onApprove:{_ in})
                        }
                    }.environment(\.locale,Locale(identifier:language))
                    let host=NSHostingView(rootView:shell)
                    let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
                    window.isReleasedWhenClosed=false;window.contentView=host
                    host.frame=NSRect(origin:.zero,size:size)
                    host.layoutSubtreeIfNeeded();await Task.yield();host.layoutSubtreeIfNeeded()
                    var splitCount=0
                    func checkColumns(_ view:NSView) {
                        if view is NSSplitView {
                            splitCount += 1
                            let frame=view.convert(view.bounds,to:host)
                            XCTAssertGreaterThan(frame.width,0)
                            XCTAssertGreaterThanOrEqual(frame.minX,host.bounds.minX-1)
                            XCTAssertLessThanOrEqual(frame.maxX,host.bounds.maxX+1)
                            XCTAssertLessThanOrEqual(frame.width,host.bounds.width+1)
                        }
                        for child in view.subviews {checkColumns(child)}
                    }
                    checkColumns(host);XCTAssertGreaterThan(splitCount,0)
                    window.contentView=nil;window.close()
                }
            }
        }
    }
}
