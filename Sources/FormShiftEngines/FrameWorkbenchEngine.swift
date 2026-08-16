import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import FormShiftCore

public enum FrameWorkbenchEngine {
    public static func splitGIF(
        gifURL: URL,
        destinationDirectory: URL,
        format: FormatID = .png,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> [URL] {
        let srcScoped = gifURL.startAccessingSecurityScopedResource()
        defer { if srcScoped { gifURL.stopAccessingSecurityScopedResource() } }
        let destScoped = destinationDirectory.startAccessingSecurityScopedResource()
        defer { if destScoped { destinationDirectory.stopAccessingSecurityScopedResource() } }

        guard let source = CGImageSourceCreateWithURL(gifURL as CFURL, nil) else {
            throw ConversionError.unsupportedInput(gifURL)
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            throw ConversionError.processFailed("GIF 中未发现有效图像帧")
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let baseName = gifURL.deletingPathExtension().lastPathComponent
        let digits = max(3, String(frameCount).count)
        var createdURLs: [URL] = []
        let total = Double(frameCount)
        let dummyOptions = ConversionOptions()

        for i in 0..<frameCount {
            guard let frame = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let numStr = String(format: "%0\(digits)d", i + 1)
            var frameURL = destinationDirectory
                .appendingPathComponent("\(baseName)_frame_\(numStr)")
                .appendingPathExtension(format.fileExtension)
            if fileManager.fileExists(atPath: frameURL.path) {
                var counter = 1
                repeat {
                    frameURL = destinationDirectory
                        .appendingPathComponent("\(baseName)_frame_\(numStr) (\(counter))")
                        .appendingPathExtension(format.fileExtension)
                    counter += 1
                } while fileManager.fileExists(atPath: frameURL.path)
            }
            try ImageRenderer.write(
                image: frame,
                sourceProperties: [:],
                to: frameURL,
                format: format,
                options: dummyOptions
            )
            createdURLs.append(frameURL)
            progress?(Double(i + 1) / total * 0.95)
        }
        progress?(1.0)
        return createdURLs
    }

    public static func createGIF(
        imageURLs: [URL],
        destinationURL: URL,
        options: FrameSequenceOptions = .init(),
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> URL {
        guard !imageURLs.isEmpty else {
            throw ConversionError.invalidOptions("未提供合成 GIF 的图片文件")
        }
        let destScoped = destinationURL.startAccessingSecurityScopedResource()
        defer { if destScoped { destinationURL.stopAccessingSecurityScopedResource() } }
        for u in imageURLs { _ = u.startAccessingSecurityScopedResource() }
        defer { for u in imageURLs { u.stopAccessingSecurityScopedResource() } }

        let fileManager = FileManager.default
        let tempURL = fileManager.temporaryDirectory
            .appendingPathComponent("formshift_gifseq_\(UUID().uuidString)")
            .appendingPathExtension("gif")
        try? fileManager.removeItem(at: tempURL)
        try fileManager.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        guard let destination = CGImageDestinationCreateWithURL(
            tempURL as CFURL,
            UTType.gif.identifier as CFString,
            imageURLs.count,
            nil
        ) else {
            throw ConversionError.processFailed("无法初始化 GIF 输出文件")
        }

        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: options.loopCount
            ]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        let fps = max(0.5, options.frameRate)
        let delay = 1.0 / fps
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay
            ]
        ]

        let total = Double(imageURLs.count)
        for (index, url) in imageURLs.enumerated() {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  var image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                try? fileManager.removeItem(at: tempURL)
                throw ConversionError.unsupportedInput(url)
            }
            if options.width != nil || options.height != nil {
                let resizeOpts = ConversionOptions(width: options.width, height: options.height, imageSizingMode: .fit)
                image = ImageRenderer.resize(image, options: resizeOpts)
            }
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
            progress?(Double(index + 1) / total * 0.9)
        }

        guard CGImageDestinationFinalize(destination) else {
            try? fileManager.removeItem(at: tempURL)
            throw ConversionError.processFailed("生成 GIF 失败")
        }

        let data = try Data(contentsOf: tempURL)
        try data.write(to: destinationURL, options: .atomic)
        try? fileManager.removeItem(at: tempURL)
        progress?(1.0)
        return destinationURL
    }

    public static func extractVideoFrames(
        videoURL: URL,
        destinationDirectory: URL,
        strategy: VideoFrameExtractionStrategy,
        format: FormatID = .png,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [URL] {
        let srcScoped = videoURL.startAccessingSecurityScopedResource()
        defer { if srcScoped { videoURL.stopAccessingSecurityScopedResource() } }
        let destScoped = destinationDirectory.startAccessingSecurityScopedResource()
        defer { if destScoped { destinationDirectory.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        guard duration > 0 else {
            throw ConversionError.unsupportedInput(videoURL)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var timestamps: [Double] = []
        switch strategy {
        case .singleTimestamp(let time):
            let t = max(0, min(time, duration))
            timestamps = [t]
        case .intervalSeconds(let interval):
            let step = max(0.1, interval)
            var current = 0.0
            while current < duration {
                timestamps.append(current)
                current += step
            }
        case .totalCount(let count):
            let n = max(1, count)
            if n == 1 {
                timestamps = [0]
            } else {
                let step = duration / Double(n - 1)
                for i in 0..<n {
                    timestamps.append(min(duration, Double(i) * step))
                }
            }
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let baseName = videoURL.deletingPathExtension().lastPathComponent
        let digits = max(3, String(timestamps.count).count)
        var createdURLs: [URL] = []
        let total = Double(timestamps.count)
        let dummyOptions = ConversionOptions()

        for (index, timeSec) in timestamps.enumerated() {
            let cmTime = CMTime(seconds: timeSec, preferredTimescale: 600)
            let (cgImage, _) = try await generator.image(at: cmTime)
            let numStr = String(format: "%0\(digits)d", index + 1)
            let timeTag = String(format: "_%02d%02d", Int(timeSec) / 60, Int(timeSec) % 60)
            var frameURL = destinationDirectory
                .appendingPathComponent("\(baseName)_frame_\(numStr)\(timeTag)")
                .appendingPathExtension(format.fileExtension)
            if fileManager.fileExists(atPath: frameURL.path) {
                var counter = 1
                repeat {
                    frameURL = destinationDirectory
                        .appendingPathComponent("\(baseName)_frame_\(numStr)\(timeTag) (\(counter))")
                        .appendingPathExtension(format.fileExtension)
                    counter += 1
                } while fileManager.fileExists(atPath: frameURL.path)
            }
            try ImageRenderer.write(
                image: cgImage,
                sourceProperties: [:],
                to: frameURL,
                format: format,
                options: dummyOptions
            )
            createdURLs.append(frameURL)
            progress?(Double(index + 1) / total * 0.95)
        }
        progress?(1.0)
        return createdURLs
    }
}
