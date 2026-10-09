import AppKit
import SwiftUI
import XCTest
@testable import WorkspaceClient

final class WorkspaceAppearanceTests:XCTestCase {
    func luminance(_ color:Color)->Double {
        let rgb=NSColor(color).usingColorSpace(.sRGB)!
        func linear(_ value:Double)->Double { value<=0.04045 ? value/12.92:pow((value+0.055)/1.055,2.4) }
        return 0.2126*linear(rgb.redComponent)+0.7152*linear(rgb.greenComponent)+0.0722*linear(rgb.blueComponent)
    }
    func testSunsetAccentsRemainReadableInBothAppearances() {
        let light=luminance(WorkspaceAppearance.accent(for:.light)),dark=luminance(WorkspaceAppearance.accent(for:.dark))
        XCTAssertGreaterThan(1.05/(light+0.05),4.5)
        XCTAssertGreaterThan((dark+0.05)/(luminance(WorkspaceAppearance.slate)+0.05),4.5)
    }
    @MainActor func testNativeGlassAndBackdropRenderAtNarrowAndWideSizes() {
        for scheme:ColorScheme in [.light,.dark] {
            for width in [560.0,1440.0] {
                let content=VStack { Button("Native action") {}.buttonStyle(.glassProminent) }
                    .padding(20).glassEffect(.regular,in:RoundedRectangle(cornerRadius:18))
                    .background(WorkspaceAppearance.backdrop(for:scheme)).environment(\.colorScheme,scheme)
                let host=NSHostingView(rootView:content)
                host.frame=NSRect(x:0,y:0,width:width,height:520);host.layoutSubtreeIfNeeded()
                XCTAssertGreaterThan(host.fittingSize.height,0)
            }
        }
    }
}
