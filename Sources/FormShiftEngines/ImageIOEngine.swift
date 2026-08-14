import Foundation
import ImageIO
import FormShiftCore

public final class ImageIOEngine: ConversionEngine, @unchecked Sendable {
    public let id = "imageio"
    public let capabilities: [ConversionCapability]

    public init() {
        // Animated GIF input is deliberately excluded: this single-output image
        // path would silently flatten it to the first frame.
        let inputs = ImageFormatSupport.decodableFormats.filter { $0 != .gif }
        let outputs = ImageFormatSupport.encodableFormats
        capabilities = inputs.flatMap { input in
            outputs.map { output in
                ConversionCapability(
                    engineID: "imageio",
                    input: input,
                    output: output,
                    supportsResize: true,
                    supportsCrop: true,
                    supportsMetadata: true
                )
            }
        }
    }

    public func probe(url: URL) async throws -> MediaDescriptor {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              let format = ImageFormatSupport.format(forTypeIdentifier: typeIdentifier),
              ImageFormatSupport.decodableFormats.contains(format),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            throw ConversionError.unsupportedInput(url)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if (5...8).contains(orientation) {
            swap(&width, &height)
        }
        return MediaDescriptor(
            url: url,
            format: format,
            byteCount: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            pixelWidth: width,
            pixelHeight: height,
            codecName: typeIdentifier
        )
    }

    public func validate(source: MediaDescriptor, output: FormatID, options: ConversionOptions) throws {
        try SharedValidation.validateCommon(options)
        guard capabilities.contains(where: { $0.input == source.format && $0.output == output }) else {
            throw ConversionError.unsupportedConversion(source.format, output)
        }
        if let crop = options.crop,
           let width = source.pixelWidth,
           let height = source.pixelHeight,
           crop.x + crop.width > width || crop.y + crop.height > height {
            throw ConversionError.invalidOptions("裁剪区域超出图片范围")
        }
    }

    public func makePlan(
        jobID: UUID,
        source: MediaDescriptor,
        output: FormatID,
        destination: URL,
        options: ConversionOptions
    ) throws -> ConversionPlan {
        try validate(source: source, output: output, options: options)
        return try SharedValidation.makePlan(
            engineID: id,
            capabilities: capabilities,
            jobID: jobID,
            source: source,
            output: output,
            destination: destination,
            options: options
        )
    }

    public func run(
        plan: ConversionPlan,
        progress: @escaping @Sendable (ConversionProgress) -> Void
    ) async throws -> URL {
        guard plan.engineID == id else {
            throw ConversionError.invalidOptions("任务不属于 ImageIO 引擎")
        }
        try Task.checkCancellation()
        try EngineFileSafety.prepareTemporaryOutput(for: plan)
        do {
            progress(.init(fraction: 0.1, detail: "正在解码图片"))
            let rendered = try ImageRenderer.loadAndRender(url: plan.source.url, options: plan.options)
            try Task.checkCancellation()
            progress(.init(fraction: 0.7, detail: "正在编码图片"))
            try ImageRenderer.write(
                image: rendered.image,
                sourceProperties: rendered.sourceProperties,
                to: plan.temporaryURL,
                format: plan.outputFormat,
                options: plan.options
            )
            try Task.checkCancellation()
            let result = try EngineFileSafety.commitTemporaryOutput(for: plan)
            progress(.init(fraction: 1, detail: "转换完成"))
            return result
        } catch is CancellationError {
            EngineFileSafety.cleanupTemporaryOutput(for: plan)
            throw ConversionError.cancelled
        } catch {
            EngineFileSafety.cleanupTemporaryOutput(for: plan)
            throw error
        }
    }

    public func cancel(jobID: UUID) async {
        // ImageIO 没有安全的中途终止 API；调用方取消 Task 后会在各阶段之间终止。
    }
}
