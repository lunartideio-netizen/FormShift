import AppKit
import SwiftUI

enum FormShiftTheme {
    static let ceramic = Color(
        nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.name.rawValue.lowercased().contains("dark") ||
                         appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0.070, green: 0.078, blue: 0.092, alpha: 1)
                : NSColor(srgbRed: 0.965, green: 0.970, blue: 0.978, alpha: 1)
        }
    )

    static let machineSilver = Color(
        nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.name.rawValue.lowercased().contains("dark") ||
                         appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0.140, green: 0.150, blue: 0.170, alpha: 1)
                : NSColor(srgbRed: 0.895, green: 0.905, blue: 0.920, alpha: 1)
        }
    )

    static let graphite = Color(
        nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.name.rawValue.lowercased().contains("dark") ||
                         appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1)
                : NSColor(srgbRed: 0.11, green: 0.13, blue: 0.15, alpha: 1)
        }
    )

    static let secondaryGraphite = Color(
        nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.name.rawValue.lowercased().contains("dark") ||
                         appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
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
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(elevated ? 0.95 : 0.80))
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(elevated ? 0.08 : 0.03), radius: elevated ? 8 : 3, x: 0, y: elevated ? 3 : 1)
    }
}

struct InspectorPicker<Content: View>: View {
    let displayTitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 6) {
                Text(displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FormShiftTheme.graphite)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
    }
}

extension View {
    func panelSurface(radius: CGFloat = 14, elevated: Bool = false) -> some View {
        modifier(PanelSurface(radius: radius, elevated: elevated))
    }
}
