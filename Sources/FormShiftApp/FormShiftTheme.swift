import AppKit
import SwiftUI

enum FormShiftTheme {
    static let ceramic = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.075, green: 0.086, blue: 0.102, alpha: 1)
                : NSColor(srgbRed: 0.969, green: 0.973, blue: 0.980, alpha: 1)
        }
    )

    static let machineSilver = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.145, green: 0.157, blue: 0.176, alpha: 1)
                : NSColor(srgbRed: 0.906, green: 0.914, blue: 0.929, alpha: 1)
        }
    )

    static let graphite = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.91, green: 0.925, blue: 0.95, alpha: 1)
                : NSColor(srgbRed: 0.125, green: 0.141, blue: 0.165, alpha: 1)
        }
    )

    static let secondaryGraphite = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.64, green: 0.67, blue: 0.72, alpha: 1)
                : NSColor(srgbRed: 0.35, green: 0.38, blue: 0.43, alpha: 1)
        }
    )

    static let cobalt = Color(red: 0.196, green: 0.404, blue: 0.890)
    static let processAmber = Color(red: 0.914, green: 0.604, blue: 0.180)
    static let success = Color(red: 0.145, green: 0.625, blue: 0.390)
    static let danger = Color(red: 0.82, green: 0.25, blue: 0.25)
    static let hairline = Color.primary.opacity(0.10)

    static func formatColor(_ format: String) -> Color {
        switch format.lowercased() {
        case "png", "heic", "webp", "avif", "gif": cobalt
        case "mp4", "mov", "mkv", "webm": Color(red: 0.36, green: 0.34, blue: 0.84)
        case "mp3", "m4a", "aac", "wav", "aiff", "flac", "alac", "ogg", "opus":
            Color(red: 0.11, green: 0.57, blue: 0.58)
        case "pdf": processAmber
        default: secondaryGraphite
        }
    }
}

struct PanelSurface: ViewModifier {
    var radius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(FormShiftTheme.hairline, lineWidth: 1)
            }
    }
}

extension View {
    func panelSurface(radius: CGFloat = 14) -> some View {
        modifier(PanelSurface(radius: radius))
    }
}
