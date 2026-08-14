import Foundation

public enum MetadataPolicy: String, Codable, CaseIterable, Sendable {
    case preserve
    case remove
}

public enum CollisionPolicy: String, Codable, CaseIterable, Sendable {
    case increment
    case skip
}

public enum VideoCodec: String, Codable, CaseIterable, Sendable {
    case automatic
    case h264
    case hevc
    case proRes
    case vp9
    case av1
}

public enum ImageSizingMode: String, Codable, CaseIterable, Sendable {
    case fit
    case fill
    case stretch
}

public enum ImageColorProfile: String, Codable, CaseIterable, Sendable {
    case automatic
    case sRGB
    case displayP3
}

public struct CropRect: Codable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct ConversionOptions: Codable, Hashable, Sendable {
    public var quality: Double
    public var width: Int?
    public var height: Int?
    public var preserveAspectRatio: Bool
    public var imageSizingMode: ImageSizingMode
    public var trimBorders: Bool
    public var crop: CropRect?
    public var rotationDegrees: Int
    public var imageColorProfile: ImageColorProfile
    public var pdfRenderScale: Int
    public var videoCodec: VideoCodec
    public var preferHardwareEncoding: Bool
    public var videoBitrateKbps: Int?
    public var audioBitrateKbps: Int?
    public var frameRate: Double?
    public var sampleRate: Int?
    public var audioChannels: Int?
    public var trimStartSeconds: Double?
    public var trimEndSeconds: Double?
    public var normalizeAudio: Bool
    public var removeAudio: Bool
    public var metadataPolicy: MetadataPolicy

    public init(
        quality: Double = 0.85,
        width: Int? = nil,
        height: Int? = nil,
        preserveAspectRatio: Bool = true,
        imageSizingMode: ImageSizingMode = .fit,
        trimBorders: Bool = false,
        crop: CropRect? = nil,
        rotationDegrees: Int = 0,
        imageColorProfile: ImageColorProfile = .automatic,
        pdfRenderScale: Int = 2,
        videoCodec: VideoCodec = .automatic,
        preferHardwareEncoding: Bool = true,
        videoBitrateKbps: Int? = nil,
        audioBitrateKbps: Int? = nil,
        frameRate: Double? = nil,
        sampleRate: Int? = nil,
        audioChannels: Int? = nil,
        trimStartSeconds: Double? = nil,
        trimEndSeconds: Double? = nil,
        normalizeAudio: Bool = false,
        removeAudio: Bool = false,
        metadataPolicy: MetadataPolicy = .preserve
    ) {
        self.quality = quality
        self.width = width
        self.height = height
        self.preserveAspectRatio = preserveAspectRatio
        self.imageSizingMode = imageSizingMode
        self.trimBorders = trimBorders
        self.crop = crop
        self.rotationDegrees = rotationDegrees
        self.imageColorProfile = imageColorProfile
        self.pdfRenderScale = pdfRenderScale
        self.videoCodec = videoCodec
        self.preferHardwareEncoding = preferHardwareEncoding
        self.videoBitrateKbps = videoBitrateKbps
        self.audioBitrateKbps = audioBitrateKbps
        self.frameRate = frameRate
        self.sampleRate = sampleRate
        self.audioChannels = audioChannels
        self.trimStartSeconds = trimStartSeconds
        self.trimEndSeconds = trimEndSeconds
        self.normalizeAudio = normalizeAudio
        self.removeAudio = removeAudio
        self.metadataPolicy = metadataPolicy
    }

    private enum CodingKeys: String, CodingKey {
        case quality, width, height, preserveAspectRatio, imageSizingMode, trimBorders, crop, rotationDegrees
        case imageColorProfile, pdfRenderScale
        case videoCodec, preferHardwareEncoding, videoBitrateKbps, audioBitrateKbps
        case frameRate, sampleRate, audioChannels, trimStartSeconds, trimEndSeconds
        case normalizeAudio, removeAudio, metadataPolicy
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        quality = try values.decodeIfPresent(Double.self, forKey: .quality) ?? 0.85
        width = try values.decodeIfPresent(Int.self, forKey: .width)
        height = try values.decodeIfPresent(Int.self, forKey: .height)
        preserveAspectRatio = try values.decodeIfPresent(Bool.self, forKey: .preserveAspectRatio) ?? true
        imageSizingMode = try values.decodeIfPresent(ImageSizingMode.self, forKey: .imageSizingMode) ?? .fit
        trimBorders = try values.decodeIfPresent(Bool.self, forKey: .trimBorders) ?? false
        crop = try values.decodeIfPresent(CropRect.self, forKey: .crop)
        rotationDegrees = try values.decodeIfPresent(Int.self, forKey: .rotationDegrees) ?? 0
        imageColorProfile = try values.decodeIfPresent(ImageColorProfile.self, forKey: .imageColorProfile) ?? .automatic
        pdfRenderScale = try values.decodeIfPresent(Int.self, forKey: .pdfRenderScale) ?? 2
        videoCodec = try values.decodeIfPresent(VideoCodec.self, forKey: .videoCodec) ?? .automatic
        preferHardwareEncoding = try values.decodeIfPresent(Bool.self, forKey: .preferHardwareEncoding) ?? true
        videoBitrateKbps = try values.decodeIfPresent(Int.self, forKey: .videoBitrateKbps)
        audioBitrateKbps = try values.decodeIfPresent(Int.self, forKey: .audioBitrateKbps)
        frameRate = try values.decodeIfPresent(Double.self, forKey: .frameRate)
        sampleRate = try values.decodeIfPresent(Int.self, forKey: .sampleRate)
        audioChannels = try values.decodeIfPresent(Int.self, forKey: .audioChannels)
        trimStartSeconds = try values.decodeIfPresent(Double.self, forKey: .trimStartSeconds)
        trimEndSeconds = try values.decodeIfPresent(Double.self, forKey: .trimEndSeconds)
        normalizeAudio = try values.decodeIfPresent(Bool.self, forKey: .normalizeAudio) ?? false
        removeAudio = try values.decodeIfPresent(Bool.self, forKey: .removeAudio) ?? false
        metadataPolicy = try values.decodeIfPresent(MetadataPolicy.self, forKey: .metadataPolicy) ?? .preserve
    }
}

public struct ConversionCapability: Codable, Hashable, Identifiable, Sendable {
    public let engineID: String
    public let input: FormatID
    public let output: FormatID
    public let supportsResize: Bool
    public let supportsCrop: Bool
    public let supportsTrim: Bool
    public let supportsMetadata: Bool

    public var id: String { "\(engineID):\(input.rawValue):\(output.rawValue)" }

    public init(
        engineID: String,
        input: FormatID,
        output: FormatID,
        supportsResize: Bool = false,
        supportsCrop: Bool = false,
        supportsTrim: Bool = false,
        supportsMetadata: Bool = false
    ) {
        self.engineID = engineID
        self.input = input
        self.output = output
        self.supportsResize = supportsResize
        self.supportsCrop = supportsCrop
        self.supportsTrim = supportsTrim
        self.supportsMetadata = supportsMetadata
    }
}

public struct ConversionPlan: Codable, Hashable, Sendable {
    public let jobID: UUID
    public let engineID: String
    public let source: MediaDescriptor
    public let outputFormat: FormatID
    public let temporaryURL: URL
    public let destinationURL: URL
    public let options: ConversionOptions

    public init(
        jobID: UUID,
        engineID: String,
        source: MediaDescriptor,
        outputFormat: FormatID,
        temporaryURL: URL,
        destinationURL: URL,
        options: ConversionOptions
    ) {
        self.jobID = jobID
        self.engineID = engineID
        self.source = source
        self.outputFormat = outputFormat
        self.temporaryURL = temporaryURL
        self.destinationURL = destinationURL
        self.options = options
    }
}

public struct ConversionProgress: Codable, Hashable, Sendable {
    public let fraction: Double
    public let detail: String?

    public init(fraction: Double, detail: String? = nil) {
        self.fraction = min(max(fraction, 0), 1)
        self.detail = detail
    }
}
