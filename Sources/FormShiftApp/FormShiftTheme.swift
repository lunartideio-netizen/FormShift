import AppKit
import SwiftUI

enum FormShiftTheme {
    static let ceramic = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.070, green: 0.078, blue: 0.092, alpha: 1)
                : NSColor(srgbRed: 0.965, green: 0.970, blue: 0.978, alpha: 1)
        }
    )

    static let machineSilver = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.140, green: 0.150, blue: 0.170, alpha: 1)
                : NSColor(srgbRed: 0.895, green: 0.905, blue: 0.920, alpha: 1)
        }
    )

    static let graphite = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1)
                : NSColor(srgbRed: 0.11, green: 0.13, blue: 0.15, alpha: 1)
        }
    )

    static let secondaryGraphite = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.60, green: 0.64, blue: 0.70, alpha: 1)
                : NSColor(srgbRed: 0.40, green: 0.44, blue: 0.49, alpha: 1)
        }
    )

    static let cobalt = Color(red: 0.14, green: 0.45, blue: 0.98)
    static let violet = Color(red: 0.52, green: 0.36, blue: 0.92)
    static let emerald = Color(red: 0.12, green: 0.68, blue: 0.48)
    static let processAmber = Color(red: 0.96, green: 0.58, blue: 0.12)
    static let coral = Color(red: 0.98, green: 0.42, blue: 0.36)
    static let success = Color(red: 0.12, green: 0.68, blue: 0.48)
    static let danger = Color(red: 0.88, green: 0.26, blue: 0.28)
    static let hairline = Color.primary.opacity(0.08)

    static func formatColor(_ format: String) -> Color {
        switch format.lowercased() {
        case "png", "jpeg", "jpg", "heic", "webp", "avif", "bmp", "tiff":
            cobalt
        case "mp4", "mov", "mkv", "webm":
            violet
        case "mp3", "m4a", "aac", "wav", "aiff", "flac", "alac", "ogg", "opus":
            emerald
        case "gif":
            coral
        case "pdf":
            processAmber
        case "docx", "doc", "xlsx", "xls", "pptx", "ppt", "rtf", "txt", "csv":
            Color(red: 0.22, green: 0.52, blue: 0.88)
        default: secondaryGraphite
        }
    }
}

struct PanelSurface: ViewModifier {
    var radius: CGFloat = 14
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(elevated ? 0.85 : 0.60))
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.primary.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(elevated ? 0.08 : 0.03), radius: elevated ? 10 : 4, x: 0, y: elevated ? 4 : 2)
    }
}

extension View {
    func panelSurface(radius: CGFloat = 14, elevated: Bool = false) -> some View {
        modifier(PanelSurface(radius: radius, elevated: elevated))
    }
}
