import SwiftUI

// Golden Gate sunset palette from the configured desktop; content stays semantic.
enum WorkspaceAppearance {
    static let copper=Color(.sRGB,red:0.70,green:0.30,blue:0.16,opacity:1)
    static let sunlight=Color(.sRGB,red:0.95,green:0.69,blue:0.49,opacity:1)
    static let ocean=Color(.sRGB,red:0.24,green:0.38,blue:0.48,opacity:1)
    static let sand=Color(.sRGB,red:0.96,green:0.94,blue:0.90,opacity:1)
    static let slate=Color(.sRGB,red:0.09,green:0.13,blue:0.18,opacity:1)
    static func accent(for scheme:ColorScheme)->Color { scheme == .dark ? sunlight:copper }
    static func backdrop(for scheme:ColorScheme)->LinearGradient {
        LinearGradient(colors:scheme == .dark ? [slate,ocean.opacity(0.30),slate]:[sand,sunlight.opacity(0.10),ocean.opacity(0.08)],startPoint:.topLeading,endPoint:.bottomTrailing)
    }
}
