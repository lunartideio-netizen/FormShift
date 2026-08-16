import Foundation
import CoreGraphics

public struct PDFPageSpec: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var originalPageIndex: Int
    public var rotationAngle: Int
    public var isIncluded: Bool

    public init(
        id: UUID = UUID(),
        originalPageIndex: Int,
        rotationAngle: Int = 0,
        isIncluded: Bool = true
    ) {
        self.id = id
        self.originalPageIndex = originalPageIndex
        self.rotationAngle = rotationAngle
        self.isIncluded = isIncluded
    }
}

public enum PDFSplitStrategy: Codable, Hashable, Sendable {
    case eachPage
    case fixedPageCount(Int)
    case pageRanges(String)
}

public enum PDFPageSizePreset: String, Codable, CaseIterable, Sendable {
    case matchImage
    case a4Portrait
    case a4Landscape
    case usLetterPortrait
    case usLetterLandscape

    public var displayName: String {
        switch self {
        case .matchImage: "适应图片尺寸"
        case .a4Portrait: "A4 纵向 (210 × 297 mm)"
        case .a4Landscape: "A4 横向 (297 × 210 mm)"
        case .usLetterPortrait: "US Letter 纵向"
        case .usLetterLandscape: "US Letter 横向"
        }
    }

    public var dimensionsPoints: CGSize? {
        switch self {
        case .matchImage: nil
        case .a4Portrait: CGSize(width: 595.28, height: 841.89)
        case .a4Landscape: CGSize(width: 841.89, height: 595.28)
        case .usLetterPortrait: CGSize(width: 612.0, height: 792.0)
        case .usLetterLandscape: CGSize(width: 792.0, height: 612.0)
        }
    }
}

public struct PDFImageMergeOptions: Codable, Hashable, Sendable {
    public var pageSizePreset: PDFPageSizePreset
    public var marginPoints: CGFloat
    public var imageQuality: Double
    public var imageColorProfile: ImageColorProfile

    public init(
        pageSizePreset: PDFPageSizePreset = .matchImage,
        marginPoints: CGFloat = 0,
        imageQuality: Double = 0.9,
        imageColorProfile: ImageColorProfile = .sRGB
    ) {
        self.pageSizePreset = pageSizePreset
        self.marginPoints = marginPoints
        self.imageQuality = imageQuality
        self.imageColorProfile = imageColorProfile
    }
}

public enum PDFPageRangeParser {
    public static func parse(_ text: String, totalPages: Int) -> [Int] {
        guard totalPages > 0 else { return [] }
        var result: Set<Int> = []
        let segments = text.split(separator: ",")
        for rawSegment in segments {
            let segment = rawSegment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !segment.isEmpty else { continue }
            if segment.contains("-") {
                let parts = segment.split(separator: "-", maxSplits: 1)
                if parts.count == 2,
                   let start = Int(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                   let end = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                    let lower = max(1, min(start, end))
                    let upper = min(totalPages, max(start, end))
                    if lower <= upper {
                        for p in lower...upper {
                            result.insert(p)
                        }
                    }
                }
            } else if let single = Int(segment), (1...totalPages).contains(single) {
                result.insert(single)
            }
        }
        return result.sorted()
    }
}
