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
    func testNativeViewportRejectsQueuedFocusLossAndRevealsCurrentControl() async {
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:300),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:400,height:300))
        let document=NSView(frame:NSRect(x:0,y:0,width:400,height:1600))
        let anchor=ProposalCompareViewportAnchor(frame:NSRect(x:0,y:1200,width:200,height:30))
        document.addSubview(anchor);scroll.documentView=document;window.contentView=scroll
        defer {window.close()}
        let original=scroll.contentView.bounds.origin
        anchor.reveal(true);anchor.reveal(false)
        await withCheckedContinuation {continuation in DispatchQueue.main.async {continuation.resume()}}
        XCTAssertEqual(scroll.contentView.bounds.origin,original,"Focus loss must invalidate queued scroll")
        anchor.reveal(true)
        await withCheckedContinuation {continuation in DispatchQueue.main.async {continuation.resume()}}
        XCTAssertNotEqual(scroll.contentView.bounds.origin,original,"Actual current native control must be revealed")
        XCTAssertTrue(scroll.contentView.bounds.contains(anchor.frame))
        let revealed=scroll.contentView.bounds.origin
        anchor.reveal(true);anchor.removeFromSuperview()
        await withCheckedContinuation {continuation in DispatchQueue.main.async {continuation.resume()}}
        XCTAssertEqual(scroll.contentView.bounds.origin,revealed,"Detached control must not trigger stale scrolling")
    }

    func testFocusedControlMovedByLayoutIsRevealedWithoutFocusIdentityChange() async {
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:300),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:400,height:300))
        let document=NSView(frame:NSRect(x:0,y:0,width:400,height:1600))
        let anchor=ProposalCompareViewportAnchor(frame:NSRect(x:0,y:100,width:200,height:30))
        document.addSubview(anchor);scroll.documentView=document;window.contentView=scroll
        defer {window.close()}
        anchor.reveal(true)
        await withCheckedContinuation {continuation in DispatchQueue.main.async {continuation.resume()}}
        XCTAssertTrue(scroll.contentView.bounds.contains(anchor.frame))
        // Reopened content grows before this same focused native control.
        anchor.setFrameOrigin(NSPoint(x:0,y:1200))
        await withCheckedContinuation {continuation in DispatchQueue.main.async {continuation.resume()}}
        XCTAssertTrue(scroll.contentView.bounds.contains(anchor.frame),"Same focus moved by layout must become visible without a new focus event")
        anchor.reveal(false);let retained=scroll.contentView.bounds.origin
        anchor.setFrameOrigin(NSPoint(x:0,y:100))
        await withCheckedContinuation {continuation in DispatchQueue.main.async {continuation.resume()}}
        XCTAssertEqual(scroll.contentView.bounds.origin,retained,"An unfocused layout change must not scroll")
    }

    func testFocusedControlKeepsVerticalBreathingRoomAtClipEdge() async {
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:300),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:400,height:300))
        let document=NSView(frame:NSRect(x:0,y:0,width:400,height:1600))
        let anchor=ProposalCompareViewportAnchor(frame:NSRect(x:20,y:270,width:200,height:30))
        document.addSubview(anchor);scroll.documentView=document;window.contentView=scroll
        defer {window.close()}
        XCTAssertTrue(scroll.contentView.bounds.contains(anchor.frame),"Positive control: fully visible but flush against clip edge")
        anchor.reveal(true)
        await withCheckedContinuation {continuation in DispatchQueue.main.async {continuation.resume()}}
        XCTAssertTrue(scroll.contentView.bounds.insetBy(dx:0,dy:12).contains(anchor.frame),"Focused control and ring must remain inside the viewport with breathing room")
        let revealed=scroll.contentView.bounds.origin
        anchor.setFrameOrigin(NSPoint(x:20,y:100))
        await withCheckedContinuation {continuation in DispatchQueue.main.async {continuation.resume()}}
        XCTAssertEqual(scroll.contentView.bounds.origin,revealed,"An already centered focus must not scroll")
        anchor.setFrameOrigin(NSPoint(x:20,y:scroll.contentView.bounds.minY))
        await withCheckedContinuation {continuation in DispatchQueue.main.async {continuation.resume()}}
        XCTAssertTrue(scroll.contentView.bounds.insetBy(dx:0,dy:12).contains(anchor.frame),"The opposite clip edge must retain the same vertical margin")
        let afterOppositeEdge=scroll.contentView.bounds.origin
        anchor.reveal(false);anchor.setFrameOrigin(NSPoint(x:20,y:1200))
        await withCheckedContinuation {continuation in DispatchQueue.main.async {continuation.resume()}}
        XCTAssertEqual(scroll.contentView.bounds.origin,afterOppositeEdge,"Unfocused layout changes must not scroll")
    }

    func testRealSwiftUIHostingRevealsFocusAfterAncestorLayoutChanges() async throws {
        let fixture=ViewportHostingFixture()
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:300),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let host=NSHostingView(rootView:ViewportHostingContent(fixture:fixture))
        window.contentView=host;window.orderFront(nil)
        defer {window.close()}
        var anchor:ProposalCompareViewportAnchor?
        let mounted=ContinuousClock.now.advanced(by:.seconds(2))
        while anchor==nil,ContinuousClock.now<mounted {
            host.layoutSubtreeIfNeeded()
            var pending:[NSView]=[host]
            while let next=pending.popLast() {if let value=next as? ProposalCompareViewportAnchor {anchor=value;break};pending+=next.subviews}
            if anchor==nil {try await Task.sleep(for:.milliseconds(10))}
        }
        let control=try XCTUnwrap(anchor,"Actual representable must mount inside real SwiftUI ScrollView")
        fixture.focused=true
        try await Task.sleep(for:.milliseconds(40));host.layoutSubtreeIfNeeded()
        XCTAssertTrue(host.bounds.insetBy(dx:0,dy:12).contains(control.convert(control.bounds,to:host)),"Positive control: initial centered hosted focus")
        fixture.prefix=1100;fixture.expanded=true
        let timeout=ContinuousClock.now.advanced(by:.seconds(2))
        repeat {
            try await Task.sleep(for:.milliseconds(10));host.layoutSubtreeIfNeeded()
        } while !host.bounds.insetBy(dx:0,dy:12).contains(control.convert(control.bounds,to:host)) && ContinuousClock.now<timeout
        XCTAssertTrue(host.bounds.insetBy(dx:0,dy:12).contains(control.convert(control.bounds,to:host)),"The actual same focused SwiftUI control must stay inside the viewport after ancestor layout changes")
    }

    func testNativeFocusRevealsControlEvenWhenCallerFocusSnapshotIsFalse() async throws {
        let fixture=ViewportHostingFixture();fixture.nativeFocus=true;fixture.callerTracksFocus=false;fixture.prefix=1100;fixture.expanded=true
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:300),styleMask:.borderless,backing:.buffered,defer:false);window.isReleasedWhenClosed=false
        let host=NSHostingView(rootView:ViewportHostingContent(fixture:fixture));window.contentView=host;window.makeKeyAndOrderFront(nil)
        defer {window.close()}
        try await Task.sleep(for:.milliseconds(100));fixture.focused=true
        let timeout=ContinuousClock.now.advanced(by:.seconds(2));var control:ProposalCompareViewportAnchor?
        repeat {
            try await Task.sleep(for:.milliseconds(10));host.layoutSubtreeIfNeeded();var pending:[NSView]=[host]
            while let next=pending.popLast() {if let anchor=next as? ProposalCompareViewportAnchor {control=anchor;break};pending+=next.subviews}
        } while (control==nil || !Mirror(reflecting:control!).children.contains(where:{$0.label=="currentFocus" && ($0.value as? Bool)==true})) && ContinuousClock.now<timeout
        let anchor=try XCTUnwrap(control)
        XCTAssertTrue(Mirror(reflecting:anchor).children.contains(where:{$0.label=="currentFocus" && ($0.value as? Bool)==true}),"The actual native focus owner must reach viewport tracking even if the parent snapshot is false")
        XCTAssertTrue(host.bounds.insetBy(dx:0,dy:12).contains(anchor.convert(anchor.bounds,to:host)),"Actual focused control must retain visible margin")
    }

    func testFocusedControlUsesWindowClippedViewportInsteadOfOversizedClipBounds() async {
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:300),styleMask:.borderless,backing:.buffered,defer:false);window.isReleasedWhenClosed=false
        let root=NSView(frame:NSRect(x:0,y:0,width:400,height:300))
        let scroll=NSScrollView(frame:NSRect(x:0,y:-100,width:400,height:400)),document=NSView(frame:NSRect(x:0,y:0,width:400,height:1600))
        let control=ProposalCompareViewportAnchor(frame:NSRect(x:20,y:300,width:180,height:22))
        document.addSubview(control);scroll.documentView=document;root.addSubview(scroll);window.contentView=root
        scroll.contentView.scroll(to:NSPoint(x:0,y:200));scroll.reflectScrolledClipView(scroll.contentView)
        defer {window.close()}
        control.reveal(true)
        try? await Task.sleep(for:.milliseconds(40))
        XCTAssertTrue(root.bounds.insetBy(dx:0,dy:12).contains(control.convert(control.bounds,to:root)),"Focused control must fit actual window even when nearest clip extends beyond ancestor/window")
    }

    func testActualFocusBindingAndReaderScrollKeepControlInsideClip() async throws {
        let fixture=ViewportHostingFixture();fixture.nativeFocus=true;fixture.useReader=true;fixture.prefix=1100;fixture.expanded=true
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:300),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let host=NSHostingView(rootView:ViewportHostingContent(fixture:fixture));window.contentView=host;window.makeKeyAndOrderFront(nil)
        defer {window.close()}
        try await Task.sleep(for:.milliseconds(100));fixture.focused=true
        var anchor:ProposalCompareViewportAnchor?
        let timeout=ContinuousClock.now.advanced(by:.seconds(2))
        repeat {
            try await Task.sleep(for:.milliseconds(10));host.layoutSubtreeIfNeeded()
            var pending:[NSView]=[host]
            while let next=pending.popLast() {if let value=next as? ProposalCompareViewportAnchor {anchor=value;break};pending+=next.subviews}
        } while (anchor==nil || !host.bounds.insetBy(dx:0,dy:12).contains(anchor!.convert(anchor!.bounds,to:host))) && ContinuousClock.now<timeout
        try await Task.sleep(for:.milliseconds(500));host.layoutSubtreeIfNeeded()
        let control=try XCTUnwrap(anchor)
        XCTAssertTrue(host.bounds.insetBy(dx:0,dy:12).contains(control.convert(control.bounds,to:host)),"Actual FocusState and reader navigation must retain focused control inside viewport")
    }

    func testAncestorSignalsKeepOverlappingFocusAndRestoreNotificationFlags() async throws {
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:300),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:400,height:300))
        let document=NSView(frame:NSRect(x:0,y:0,width:400,height:1600))
        let container=NSView(frame:NSRect(x:0,y:100,width:400,height:100))
        let first=ProposalCompareViewportAnchor(frame:NSRect(x:20,y:10,width:150,height:22)),second=ProposalCompareViewportAnchor(frame:NSRect(x:20,y:40,width:150,height:22))
        container.addSubview(first);container.addSubview(second);document.addSubview(container);scroll.documentView=document;window.contentView=scroll
        defer {window.close()}
        let frames=container.postsFrameChangedNotifications,bounds=container.postsBoundsChangedNotifications
        first.reveal(true);second.reveal(true);first.reveal(false)
        try await Task.sleep(for:.milliseconds(20))
        XCTAssertTrue(container.postsFrameChangedNotifications);XCTAssertTrue(container.postsBoundsChangedNotifications)
        scroll.contentView.scroll(to:NSPoint(x:0,y:500));scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for:.milliseconds(40))
        XCTAssertEqual(scroll.contentView.bounds.minY,500,"Manual scrolling must not be pulled back to old focus")
        container.setFrameOrigin(NSPoint(x:0,y:1100))
        let timeout=ContinuousClock.now.advanced(by:.seconds(1))
        while !scroll.contentView.bounds.insetBy(dx:0,dy:12).contains(second.convert(second.bounds,to:document)),ContinuousClock.now<timeout {try await Task.sleep(for:.milliseconds(10))}
        XCTAssertTrue(scroll.contentView.bounds.insetBy(dx:0,dy:12).contains(second.convert(second.bounds,to:document)),"Ancestor motion must reveal the remaining focused control")
        second.reveal(false)
        let cleanup=ContinuousClock.now.advanced(by:.seconds(1))
        while container.postsFrameChangedNotifications != frames || container.postsBoundsChangedNotifications != bounds {
            if ContinuousClock.now>=cleanup {break}
            try await Task.sleep(for:.milliseconds(10))
        }
        XCTAssertEqual(container.postsFrameChangedNotifications,frames);XCTAssertEqual(container.postsBoundsChangedNotifications,bounds)
    }

}

@MainActor private final class ViewportHostingFixture:ObservableObject {
    var callerTracksFocus=true
    var nativeFocus=false
    var useReader=false
    @Published var prefix:CGFloat=100
    @Published var focused=false
    @Published var expanded=false
}
@MainActor private struct ViewportHostingContent:View {
    @ObservedObject var fixture:ViewportHostingFixture
    @FocusState private var nativeFocused:Bool
    var body:some View {
        ScrollViewReader {proxy in
        ScrollView {
            VStack(alignment:.leading,spacing:0) {
                Color.clear.frame(height:fixture.prefix)
                VStack(alignment:.leading,spacing:8) {
                    Text("Original document opener")
                    ProposalCompareControl(title:"Return to original document opener",focused:fixture.nativeFocus ? (fixture.callerTracksFocus && nativeFocused):fixture.focused) {}.focused($nativeFocused)
                    if fixture.expanded {Text(String(repeating:"Original Dutch vision\n",count:20))}
                }.padding(12).id("card")
                Color.clear.frame(height:1000)
            }
        }
        .onChange(of:fixture.focused) {_,value in if fixture.nativeFocus {nativeFocused=value;if fixture.useReader {proxy.scrollTo("card",anchor:.top)}}}
        }
    }
}
