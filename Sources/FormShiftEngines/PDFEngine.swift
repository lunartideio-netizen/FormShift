import CoreGraphics
import Foundation
import ImageIO
import FormShiftCore

public final class PDFEngine: ConversionEngine, @unchecked Sendable {
    public let id = "pdfkit"
    public let capabilities: [ConversionCapability]

    public init() {
        let imageInputs = ImageFormatSupport.decodableFormats.filter { $0 != .gif }
        let imageOutputs = ImageFormatSupport.encodableFormats.filter {
            $0 == .jpeg || $0 == .png || $0 == .tiff
        }
        var available = imageInputs.map {
            ConversionCapability(
                engineID: "pdfkit",
                input: $0,
                output: .pdf,
                supportsResize: true,
                supportsCrop: true,
                supportsMetadata: false
            )
        }
        available += imageOutputs.map {
            ConversionCapability(
                engineID: "pdfkit",
                input: .pdf,
                output: $0,
                supportsResize: true,
                supportsCrop: false,
                supportsMetadata: false
            )
        }
        capabilities = available
    }

    public func probe(url: URL) async throws -> MediaDescriptor {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw ConversionError.permissionDenied(url)
        }
        let header = try Data(contentsOf: url, options: [.mappedIfSafe]).prefix(5)
        if header == Data("%PDF-".utf8),
           let document = CGPDFDocument(url as CFURL), document.numberOfPages > 0 {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let page = document.page(at: 1)
            let bounds = page?.getBoxRect(.mediaBox) ?? .zero
            return MediaDescriptor(
                url: url,
                format: .pdf,
                byteCount: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
                pixelWidth: Int(bounds.width.rounded()),
                pixelHeight: Int(bounds.height.rounded()),
                codecName: "PDF (\(document.numberOfPages) pages)"
            )
        }

        // This engine also owns image → PDF. Probe those inputs through
        // ImageIO so detection uses the real file header instead of trusting
        // the extension.
        let image = try await ImageIOEngine().probe(url: url)
        guard capabilities.contains(where: { $0.input == image.format && $0.output == .pdf }) else {
            throw ConversionError.unsupportedInput(url)
        }
        return image
    }

    public func validate(source: MediaDescriptor, output: FormatID, options: ConversionOptions) throws {
        try SharedValidation.validateCommon(options)
        guard capabilities.contains(where: { $0.input == source.format && $0.output == output }) else {
            throw ConversionError.unsupportedConversion(source.format, output)
        }
        if source.format == .pdf, options.crop != nil {
            throw ConversionError.invalidOptions("PDF 首页导出暂不支持裁剪")
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
            throw ConversionError.invalidOptions("任务不属于 PDF 引擎")
        }
        try Task.checkCancellation()
        try EngineFileSafety.prepareTemporaryOutput(for: plan)
        do {
            progress(.init(fraction: 0.1, detail: "正在读取文件"))
            if plan.source.format == .pdf {
                try exportFirstPDFPage(plan: plan, progress: progress)
            } else {
                try createSinglePagePDF(plan: plan, progress: progress)
            }
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
        // Core Graphics PDF 操作为同步操作；Task 取消会在阶段边界生效。
    }

    private func exportFirstPDFPage(
        plan: ConversionPlan,
        progress: @escaping @Sendable (ConversionProgress) -> Void
    ) throws {
        guard let document = CGPDFDocument(plan.source.url as CFURL),
              let page = document.page(at: 1) else {
            throw ConversionError.unsupportedInput(plan.source.url)
        }
        let pageBox = page.getBoxRect(.mediaBox)
        let targetSize = plan.options.trimBorders
            ? CGSize(
                width: max(1, pageBox.width * CGFloat(plan.options.pdfRenderScale)),
                height: max(1, pageBox.height * CGFloat(plan.options.pdfRenderScale))
            )
            : resolvedPDFRasterSize(pageBox: pageBox, options: plan.options)
        let colorSpace = ImageRenderer.outputColorSpace(for: plan.options.imageColorProfile)
        guard
              let context = CGContext(
                data: nil,
                width: Int(targetSize.width),
                height: Int(targetSize.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw ConversionError.processFailed("无法创建 PDF 页面画布")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: targetSize))
        let targetRect = CGRect(origin: .zero, size: targetSize)
        let drawingRect = pdfDrawingRect(
            pageBox: pageBox,
            targetRect: targetRect,
            rotationDegrees: plan.options.rotationDegrees,
            mode: plan.options.trimBorders ? .fit : plan.options.imageSizingMode
        )
        context.concatenate(page.getDrawingTransform(
            .mediaBox,
            rect: drawingRect,
            rotate: Int32(plan.options.rotationDegrees),
            preserveAspectRatio: plan.options.imageSizingMode != .stretch
        ))
        context.drawPDFPage(page)
        guard var image = context.makeImage() else {
            throw ConversionError.processFailed("无法渲染 PDF 首页")
        }
        if plan.options.trimBorders {
            image = ImageRenderer.trimBorders(in: image)
            image = ImageRenderer.resize(image, options: plan.options)
        }
        progress(.init(fraction: 0.7, detail: "正在导出 PDF 首页"))
        try ImageRenderer.write(
            image: image,
            sourceProperties: [:],
            to: plan.temporaryURL,
            format: plan.outputFormat,
            options: plan.options
        )
    }

    private func createSinglePagePDF(
        plan: ConversionPlan,
        progress: @escaping @Sendable (ConversionProgress) -> Void
    ) throws {
        let rendered = try ImageRenderer.loadAndRender(url: plan.source.url, options: plan.options)
        var mediaBox = CGRect(
            x: 0,
            y: 0,
            width: rendered.image.width,
            height: rendered.image.height
        )
        guard let consumer = CGDataConsumer(url: plan.temporaryURL as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ConversionError.processFailed("无法创建 PDF 输出")
        }
        progress(.init(fraction: 0.7, detail: "正在写入单页 PDF"))
        context.beginPDFPage(nil)
        context.draw(rendered.image, in: mediaBox)
        context.endPDFPage()
        context.closePDF()
    }

    private func resolvedPDFRasterSize(pageBox: CGRect, options: ConversionOptions) -> CGSize {
        switch (options.width, options.height) {
        case let (width?, height?):
            if options.imageSizingMode == .fit {
                let scale = min(CGFloat(width) / pageBox.width, CGFloat(height) / pageBox.height)
                return CGSize(
                    width: max(CGFloat(1), (pageBox.width * scale).rounded()),
                    height: max(CGFloat(1), (pageBox.height * scale).rounded())
                )
            }
            return CGSize(width: width, height: height)
        case let (width?, nil):
            return CGSize(width: CGFloat(width), height: max(CGFloat(1), (CGFloat(width) * pageBox.height / pageBox.width).rounded()))
        case let (nil, height?):
            return CGSize(width: max(CGFloat(1), (CGFloat(height) * pageBox.width / pageBox.height).rounded()), height: CGFloat(height))
        case (nil, nil):
            let scale = CGFloat(options.pdfRenderScale)
            return CGSize(width: max(1, pageBox.width * scale), height: max(1, pageBox.height * scale))
        }
    }

    private func pdfDrawingRect(
        pageBox: CGRect,
        targetRect: CGRect,
        rotationDegrees: Int,
        mode: ImageSizingMode
    ) -> CGRect {
        guard mode == .fill else { return targetRect }
        let normalizedRotation = abs(rotationDegrees) % 180
        let pageSize = normalizedRotation == 90
            ? CGSize(width: pageBox.height, height: pageBox.width)
            : pageBox.size
        guard pageSize.width > 0, pageSize.height > 0 else { return targetRect }
        let scale = max(targetRect.width / pageSize.width, targetRect.height / pageSize.height)
        let drawingSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        return CGRect(
            x: targetRect.midX - drawingSize.width / 2,
            y: targetRect.midY - drawingSize.height / 2,
            width: drawingSize.width,
            height: drawingSize.height
        )
    }
}
