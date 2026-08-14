import Foundation
import UniformTypeIdentifiers

public enum MediaCategory: String, Codable, CaseIterable, Sendable {
    case image
    case video
    case audio
    case pdf
    case animatedImage

    public var displayName: String {
        switch self {
        case .image: "图片"
        case .video: "视频"
        case .audio: "音频"
        case .pdf: "PDF"
        case .animatedImage: "GIF"
        }
    }
}

public enum FormatID: String, Codable, CaseIterable, Identifiable, Sendable {
    case jpeg, png, heic, tiff, bmp, webp, avif, gif
    case mp4, mov, mkv, webm
    case mp3, m4a, aac, wav, aiff, flac, alac, ogg, opus
    case pdf

    public var id: String { rawValue }
    public var fileExtension: String { rawValue == "jpeg" ? "jpg" : rawValue }
    public var displayName: String { rawValue.uppercased() }

    public var category: MediaCategory {
        switch self {
        case .jpeg, .png, .heic, .tiff, .bmp, .webp, .avif:
            .image
        case .gif:
            .animatedImage
        case .mp4, .mov, .mkv, .webm:
            .video
        case .mp3, .m4a, .aac, .wav, .aiff, .flac, .alac, .ogg, .opus:
            .audio
        case .pdf:
            .pdf
        }
    }

    public static func from(url: URL) -> FormatID? {
        let ext = url.pathExtension.lowercased()
        if ext == "jpg" { return .jpeg }
        if ext == "heif" { return .heic }
        return FormatID(rawValue: ext)
    }
}

public struct MediaDescriptor: Codable, Hashable, Sendable {
    public let url: URL
    public let format: FormatID
    public var byteCount: Int64
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var durationSeconds: Double?
    public var frameRate: Double?
    public var hasAudio: Bool?
    public var codecName: String?

    public init(
        url: URL,
        format: FormatID,
        byteCount: Int64 = 0,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        durationSeconds: Double? = nil,
        frameRate: Double? = nil,
        hasAudio: Bool? = nil,
        codecName: String? = nil
    ) {
        self.url = url
        self.format = format
        self.byteCount = byteCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.durationSeconds = durationSeconds
        self.frameRate = frameRate
        self.hasAudio = hasAudio
        self.codecName = codecName
    }
}
