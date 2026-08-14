import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import FormShiftCore

enum EngineFileSafety {
    static func prepareTemporaryOutput(for plan: ConversionPlan) throws {
        let expectedTemporaryURL = FileSafety.temporaryURL(
            for: plan.destinationURL,
            jobID: plan.jobID
        ).standardizedFileURL
        guard plan.temporaryURL.standardizedFileURL == expectedTemporaryURL else {
            throw ConversionError.invalidOptions("临时文件路径不合法")
        }
        guard plan.destinationURL.standardizedFileURL != plan.source.url.standardizedFileURL else {
            throw ConversionError.invalidOptions("输出文件不能覆盖源文件")
        }
        guard plan.temporaryURL.standardizedFileURL != plan.source.url.standardizedFileURL else {
            throw ConversionError.invalidOptions("临时文件不能覆盖源文件")
        }

        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: plan.destinationURL.path) else {
            throw ConversionError.invalidOptions("输出文件已存在")
        }

        if fileManager.fileExists(atPath: plan.temporaryURL.path) {
            try fileManager.removeItem(at: plan.temporaryURL)
        }
        try fileManager.createDirectory(
            at: plan.temporaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    static func commitTemporaryOutput(for plan: ConversionPlan) throws -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: plan.temporaryURL.path) else {
            throw ConversionError.outputMissing
        }
        guard !fileManager.fileExists(atPath: plan.destinationURL.path) else {
            throw ConversionError.invalidOptions("输出文件已存在")
        }
        try fileManager.moveItem(at: plan.temporaryURL, to: plan.destinationURL)
        return plan.destinationURL
    }

    static func cleanupTemporaryOutput(for plan: ConversionPlan) {
        try? FileManager.default.removeItem(at: plan.temporaryURL)
    }
}

enum ImageFormatSupport {
    static let typeIdentifiers: [FormatID: String] = [
        .jpeg: UTType.jpeg.identifier,
        .png: UTType.png.identifier,
        .heic: UTType.heic.identifier,
        .tiff: UTType.tiff.identifier,
        .bmp: UTType.bmp.identifier,
        .webp: UTType.webP.identifier,
        .avif: "public.avif",
        .gif: UTType.gif.identifier
    ]

    static let imageFormats: [FormatID] = [
        .jpeg, .png, .heic, .tiff, .bmp, .webp, .avif, .gif
    ]

    static func format(forTypeIdentifier identifier: String) -> FormatID? {
        if let exact = typeIdentifiers.first(where: { $0.value == identifier })?.key {
            return exact
        }
        guard let type = UTType(identifier) else { return nil }
        return typeIdentifiers.first { _, candidateIdentifier in
            guard let candidate = UTType(candidateIdentifier) else { return false }
            return type.conforms(to: candidate)
        }?.key
    }

    static var decodableFormats: Set<FormatID> {
        let identifiers = Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
        return Set(imageFormats.filter { format in
            guard let identifier = typeIdentifiers[format] else { return false }
            return identifiers.contains(identifier)
        })
    }

    static var encodableFormats: Set<FormatID> {
        let identifiers = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        return Set(imageFormats.filter { format in
            guard let identifier = typeIdentifiers[format] else { return false }
            return identifiers.contains(identifier)
        })
    }
}

enum ImageRenderer {
    struct RenderedImage {
        let image: CGImage
        let sourceProperties: [CFString: Any]
    }

    static func loadAndRender(url: URL, options: ConversionOptions) throws -> RenderedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ConversionError.unsupportedInput(url)
        }

        let rawProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let orientationValue = rawProperties[kCGImagePropertyOrientation] as? NSNumber
        let orientation = Int32(orientationValue?.intValue ?? 1)

        var rendered = CIImage(cgImage: image).oriented(forExifOrientation: orientation)
        rendered = normalized(rendered)

        if options.trimBorders {
            rendered = smartTrimmed(rendered)
        }

        if let crop = options.crop {
            let extent = rendered.extent.integral
            let cropRect = CGRect(
                x: extent.minX + CGFloat(crop.x),
                y: extent.maxY - CGFloat(crop.y + crop.height),
                width: CGFloat(crop.width),
                height: CGFloat(crop.height)
            )
            guard extent.contains(cropRect), !cropRect.isEmpty else {
                throw ConversionError.invalidOptions("裁剪区域超出图片范围")
            }
            rendered = normalized(rendered.cropped(to: cropRect))
        }

        if options.rotationDegrees != 0 {
            let radians = CGFloat(options.rotationDegrees) * .pi / 180
            rendered = normalized(rendered.transformed(by: CGAffineTransform(rotationAngle: radians)))
        }

        if options.width != nil || options.height != nil {
            rendered = resized(
                rendered,
                requestedWidth: options.width,
                requestedHeight: options.height,
                mode: options.imageSizingMode
            )
        }

        let context = CIContext(options: [.cacheIntermediates: false])
        let colorSpace = outputColorSpace(for: options.imageColorProfile, fallback: image.colorSpace)
        guard let output = context.createCGImage(
            rendered,
            from: rendered.extent.integral,
            format: .RGBA8,
            colorSpace: colorSpace
        ) else {
            throw ConversionError.processFailed("无法渲染图片")
        }
        return RenderedImage(image: output, sourceProperties: rawProperties)
    }

    static func write(
        image: CGImage,
        sourceProperties: [CFString: Any],
        to url: URL,
        format: FormatID,
        options: ConversionOptions
    ) throws {
        guard let typeIdentifier = ImageFormatSupport.typeIdentifiers[format],
              ImageFormatSupport.encodableFormats.contains(format) else {
            throw ConversionError.processFailed("系统不支持编码 \(format.displayName)")
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            typeIdentifier as CFString,
            1,
            nil
        ) else {
            throw ConversionError.outputPermissionDenied(url.deletingLastPathComponent())
        }

        var properties: [CFString: Any] = options.metadataPolicy == .preserve ? sourceProperties : [:]
        properties[kCGImagePropertyOrientation] = 1
        properties[kCGImagePropertyPixelWidth] = image.width
        properties[kCGImagePropertyPixelHeight] = image.height
        if format == .jpeg || format == .heic || format == .webp || format == .avif {
            properties[kCGImageDestinationLossyCompressionQuality] = options.quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.processFailed("图片编码失败")
        }
    }

    private static func normalized(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(
            translationX: -image.extent.minX,
            y: -image.extent.minY
        ))
    }

    static func outputColorSpace(
        for profile: ImageColorProfile,
        fallback: CGColorSpace? = nil
    ) -> CGColorSpace {
        switch profile {
        case .automatic:
            return fallback ?? CGColorSpace(name: CGColorSpace.sRGB)!
        case .sRGB:
            return CGColorSpace(name: CGColorSpace.sRGB)!
        case .displayP3:
            return CGColorSpace(name: CGColorSpace.displayP3)!
        }
    }

    static func trimBorders(in image: CGImage) -> CGImage {
        let source = CIImage(cgImage: image)
        let trimmed = smartTrimmed(source)
        guard trimmed.extent.integral != source.extent.integral else { return image }
        let context = CIContext(options: [.cacheIntermediates: false])
        return context.createCGImage(trimmed, from: trimmed.extent.integral) ?? image
    }

    static func resize(_ image: CGImage, options: ConversionOptions) -> CGImage {
        guard options.width != nil || options.height != nil else { return image }
        let rendered = resized(
            CIImage(cgImage: image),
            requestedWidth: options.width,
            requestedHeight: options.height,
            mode: options.imageSizingMode
        )
        let context = CIContext(options: [.cacheIntermediates: false])
        return context.createCGImage(
            rendered,
            from: rendered.extent.integral,
            format: .RGBA8,
            colorSpace: outputColorSpace(for: options.imageColorProfile, fallback: image.colorSpace)
        ) ?? image
    }

    private static func smartTrimmed(_ image: CIImage) -> CIImage {
        let normalizedImage = normalized(image)
        let extent = normalizedImage.extent.integral
        guard extent.width > 2, extent.height > 2 else { return normalizedImage }

        let maximumSampleDimension: CGFloat = 512
        let sampleScale = min(1, maximumSampleDimension / max(extent.width, extent.height))
        let sampleWidth = max(1, Int((extent.width * sampleScale).rounded()))
        let sampleHeight = max(1, Int((extent.height * sampleScale).rounded()))
        let sampled = normalizedImage.transformed(by: CGAffineTransform(scaleX: sampleScale, y: sampleScale))
        let sampleBounds = CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CIContext(options: [.cacheIntermediates: false])
        var pixels = [UInt8](repeating: 255, count: sampleWidth * sampleHeight * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            context.render(
                sampled,
                toBitmap: baseAddress,
                rowBytes: sampleWidth * 4,
                bounds: sampleBounds,
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }

        var minX = sampleWidth
        var minY = sampleHeight
        var maxX = -1
        var maxY = -1
        for y in 0..<sampleHeight {
            for x in 0..<sampleWidth {
                let offset = (y * sampleWidth + x) * 4
                let red = pixels[offset]
                let green = pixels[offset + 1]
                let blue = pixels[offset + 2]
                let alpha = pixels[offset + 3]
                let isBorder = alpha <= 8 || (red >= 248 && green >= 248 && blue >= 248)
                guard !isBorder else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return normalizedImage }

        let padding = 2
        minX = max(0, minX - padding)
        minY = max(0, minY - padding)
        maxX = min(sampleWidth - 1, maxX + padding)
        maxY = min(sampleHeight - 1, maxY + padding)
        let inverseScale = 1 / sampleScale
        let cropRect = CGRect(
            x: CGFloat(minX) * inverseScale,
            y: CGFloat(minY) * inverseScale,
            width: CGFloat(maxX - minX + 1) * inverseScale,
            height: CGFloat(maxY - minY + 1) * inverseScale
        ).intersection(extent)
        guard cropRect.width > 1, cropRect.height > 1 else { return normalizedImage }
        return normalized(normalizedImage.cropped(to: cropRect.integral))
    }

    private static func resized(
        _ image: CIImage,
        requestedWidth: Int?,
        requestedHeight: Int?,
        mode: ImageSizingMode
    ) -> CIImage {
        let normalizedImage = normalized(image)
        let sourceSize = normalizedImage.extent.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return normalizedImage }

        switch (requestedWidth, requestedHeight) {
        case let (width?, height?):
            let target = CGSize(width: width, height: height)
            if mode == .stretch {
                return normalized(normalizedImage.transformed(by: CGAffineTransform(
                    scaleX: target.width / sourceSize.width,
                    y: target.height / sourceSize.height
                )))
            }
            let scale = mode == .fill
                ? max(target.width / sourceSize.width, target.height / sourceSize.height)
                : min(target.width / sourceSize.width, target.height / sourceSize.height)
            var scaled = normalized(normalizedImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale)))
            if mode == .fill {
                let crop = CGRect(
                    x: max(0, (scaled.extent.width - target.width) / 2),
                    y: max(0, (scaled.extent.height - target.height) / 2),
                    width: target.width,
                    height: target.height
                )
                scaled = normalized(scaled.cropped(to: crop.integral))
            }
            return scaled
        case let (width?, nil):
            let scale = CGFloat(width) / sourceSize.width
            return normalized(normalizedImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale)))
        case let (nil, height?):
            let scale = CGFloat(height) / sourceSize.height
            return normalized(normalizedImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale)))
        case (nil, nil):
            return normalizedImage
        }
    }

    private static func resolvedSize(
        sourceWidth: CGFloat,
        sourceHeight: CGFloat,
        requestedWidth: Int?,
        requestedHeight: Int?,
        preserveAspectRatio: Bool
    ) -> CGSize {
        switch (requestedWidth, requestedHeight) {
        case let (width?, height?):
            if preserveAspectRatio {
                let scale = min(CGFloat(width) / sourceWidth, CGFloat(height) / sourceHeight)
                return CGSize(
                    width: max(CGFloat(1), (sourceWidth * scale).rounded()),
                    height: max(CGFloat(1), (sourceHeight * scale).rounded())
                )
            }
            return CGSize(width: width, height: height)
        case let (width?, nil):
            return CGSize(width: CGFloat(width), height: max(CGFloat(1), (CGFloat(width) * sourceHeight / sourceWidth).rounded()))
        case let (nil, height?):
            return CGSize(width: max(CGFloat(1), (CGFloat(height) * sourceWidth / sourceHeight).rounded()), height: CGFloat(height))
        case (nil, nil):
            return CGSize(width: sourceWidth, height: sourceHeight)
        }
    }
}

enum SharedValidation {
    static func validateCommon(_ options: ConversionOptions) throws {
        guard options.quality >= 0, options.quality <= 1 else {
            throw ConversionError.invalidOptions("质量必须在 0 到 1 之间")
        }
        if let width = options.width, width <= 0 {
            throw ConversionError.invalidOptions("宽度必须大于 0")
        }
        if let height = options.height, height <= 0 {
            throw ConversionError.invalidOptions("高度必须大于 0")
        }
        guard (1...3).contains(options.pdfRenderScale) else {
            throw ConversionError.invalidOptions("PDF 渲染精度必须在 1× 到 3× 之间")
        }
        if let crop = options.crop,
           crop.x < 0 || crop.y < 0 || crop.width <= 0 || crop.height <= 0 {
            throw ConversionError.invalidOptions("裁剪区域无效")
        }
        guard options.rotationDegrees.isMultiple(of: 90) else {
            throw ConversionError.invalidOptions("旋转角度必须是 90 的倍数")
        }
        if let start = options.trimStartSeconds, start < 0 {
            throw ConversionError.invalidOptions("开始时间不能小于 0")
        }
        if let end = options.trimEndSeconds, end < 0 {
            throw ConversionError.invalidOptions("结束时间不能小于 0")
        }
        if let start = options.trimStartSeconds,
           let end = options.trimEndSeconds,
           end <= start {
            throw ConversionError.invalidOptions("结束时间必须晚于开始时间")
        }
    }

    static func makePlan(
        engineID: String,
        capabilities: [ConversionCapability],
        jobID: UUID,
        source: MediaDescriptor,
        output: FormatID,
        destination: URL,
        options: ConversionOptions
    ) throws -> ConversionPlan {
        guard capabilities.contains(where: { $0.input == source.format && $0.output == output }) else {
            throw ConversionError.unsupportedConversion(source.format, output)
        }
        guard destination.standardizedFileURL != source.url.standardizedFileURL else {
            throw ConversionError.invalidOptions("输出文件不能覆盖源文件")
        }
        return ConversionPlan(
            jobID: jobID,
            engineID: engineID,
            source: source,
            outputFormat: output,
            temporaryURL: FileSafety.temporaryURL(for: destination, jobID: jobID),
            destinationURL: destination,
            options: options
        )
    }
}
