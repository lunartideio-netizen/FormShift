import Foundation
import CoreGraphics

public enum VideoFrameExtractionStrategy: Codable, Hashable, Sendable {
    case singleTimestamp(Double)
    case intervalSeconds(Double)
    case totalCount(Int)
}

public struct FrameSequenceOptions: Codable, Hashable, Sendable {
    public var frameRate: Double
    public var loopCount: Int
    public var width: Int?
    public var height: Int?
    public var quality: Double

    public init(
        frameRate: Double = 15,
        loopCount: Int = 0,
        width: Int? = nil,
        height: Int? = nil,
        quality: Double = 0.9
    ) {
        self.frameRate = frameRate
        self.loopCount = loopCount
        self.width = width
        self.height = height
        self.quality = quality
    }
}
