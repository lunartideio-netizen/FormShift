import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import FormShiftCore

public enum PDFWorkbenchEngine {
    public static func createPDF(
        fromImages imageURLs: [URL],
        destinationURL: URL,
        options: PDFImageMergeOptions = .init(),
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> URL {
        guard !imageURLs.isEmpty else {
            throw ConversionError.invalidOptions("未选择图片文件")
        }
        let fileManager = FileManager.default
        let tempURL = FileSafety.temporaryURL(for: destinationURL, jobID: UUID())
        try? fileManager.removeItem(at: tempURL)
        try fileManager.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let pdfDoc = PDFDocument()
        let total = Double(imageURLs.count)

        for (index, imageURL) in imageURLs.enumerated() {
            guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let rawImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                try? fileManager.removeItem(at: tempURL)
                throw ConversionError.unsupportedInput(imageURL)
            }

            let rawProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
            let orientationValue = rawProperties[kCGImagePropertyOrientation] as? NSNumber
            let orientation = Int32(orientationValue?.intValue ?? 1)

            let ciImage = CIImage(cgImage: rawImage).oriented(forExifOrientation: orientation)
            let extent = ciImage.extent.integral
            let context = CIContext(options: [.cacheIntermediates: false])
            let colorSpace = ImageRenderer.outputColorSpace(for: options.imageColorProfile, fallback: rawImage.colorSpace)
            guard let orientedImage = context.createCGImage(ciImage, from: extent, format: .RGBA8, colorSpace: colorSpace) else {
                try? fileManager.removeItem(at: tempURL)
                throw ConversionError.processFailed("无法渲染图片：\(imageURL.lastPathComponent)")
            }

            let page: PDFPage?
            if let fixedDimensions = options.pageSizePreset.dimensionsPoints {
                let pageRect = CGRect(origin: .zero, size: fixedDimensions)
                let margin = max(0, options.marginPoints)
                let drawRect = pageRect.insetBy(dx: margin, dy: margin)
                let imgSize = CGSize(width: orientedImage.width, height: orientedImage.height)
                let scale = min(drawRect.width / imgSize.width, drawRect.height / imgSize.height)
                let fittedSize = CGSize(width: (imgSize.width * scale).rounded(), height: (imgSize.height * scale).rounded())
                let centeredRect = CGRect(
                    x: drawRect.midX - fittedSize.width / 2,
                    y: drawRect.midY - fittedSize.height / 2,
                    width: fittedSize.width,
                    height: fittedSize.height
                )
                let imageWithPage = drawImageOnPage(orientedImage, pageRect: pageRect, drawRect: centeredRect, colorSpace: colorSpace)
                if let img = imageWithPage {
                    page = PDFPage(image: NSImage(cgImage: img, size: pageRect.size))
                } else {
                    page = PDFPage(image: NSImage(cgImage: orientedImage, size: imgSize))
                }
            } else {
                let imgSize = CGSize(width: orientedImage.width, height: orientedImage.height)
                page = PDFPage(image: NSImage(cgImage: orientedImage, size: imgSize))
            }

            if let validPage = page {
                pdfDoc.insert(validPage, at: pdfDoc.pageCount)
            }
            progress?(Double(index + 1) / total * 0.9)
        }

        guard pdfDoc.write(to: tempURL) else {
            try? fileManager.removeItem(at: tempURL)
            throw ConversionError.processFailed("写入 PDF 失败")
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: tempURL, to: destinationURL)
        progress?(1.0)
        return destinationURL
    }

    public static func mergePDFs(
        pdfURLs: [URL],
        destinationURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> URL {
        guard !pdfURLs.isEmpty else {
            throw ConversionError.invalidOptions("未选择要合并的 PDF 文件")
        }
        let fileManager = FileManager.default
        let tempURL = FileSafety.temporaryURL(for: destinationURL, jobID: UUID())
        try? fileManager.removeItem(at: tempURL)
        try fileManager.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let mergedDoc = PDFDocument()
        let total = Double(pdfURLs.count)

        for (fileIndex, url) in pdfURLs.enumerated() {
            guard let sourceDoc = PDFDocument(url: url) else {
                try? fileManager.removeItem(at: tempURL)
                throw ConversionError.unsupportedInput(url)
            }
            for pageIndex in 0..<sourceDoc.pageCount {
                if let page = sourceDoc.page(at: pageIndex) {
                    mergedDoc.insert(page, at: mergedDoc.pageCount)
                }
            }
            progress?(Double(fileIndex + 1) / total * 0.9)
        }

        guard mergedDoc.write(to: tempURL) else {
            try? fileManager.removeItem(at: tempURL)
            throw ConversionError.processFailed("合并 PDF 写入失败")
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: tempURL, to: destinationURL)
        progress?(1.0)
        return destinationURL
    }

    public static func splitPDF(
        pdfURL: URL,
        destinationDirectory: URL,
        strategy: PDFSplitStrategy,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> [URL] {
        guard let sourceDoc = PDFDocument(url: pdfURL), sourceDoc.pageCount > 0 else {
            throw ConversionError.unsupportedInput(pdfURL)
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let baseName = pdfURL.deletingPathExtension().lastPathComponent
        let totalPages = sourceDoc.pageCount

        let pageGroups: [(name: String, pages: [Int])]
        switch strategy {
        case .eachPage:
            let digits = max(2, String(totalPages).count)
            pageGroups = (1...totalPages).map { p in
                let numStr = String(format: "%0\(digits)d", p)
                return ("\(baseName)_第\(numStr)页", [p])
            }
        case .fixedPageCount(let count):
            let chunkSize = max(1, count)
            var groups: [(name: String, pages: [Int])] = []
            var currentStart = 1
            var partNumber = 1
            while currentStart <= totalPages {
                let currentEnd = min(totalPages, currentStart + chunkSize - 1)
                let range = Array(currentStart...currentEnd)
                let name = "\(baseName)_分卷\(partNumber)_第\(currentStart)-\(currentEnd)页"
                groups.append((name, range))
                currentStart += chunkSize
                partNumber += 1
            }
            pageGroups = groups
        case .pageRanges(let text):
            let segments = text.split(separator: ",")
            var groups: [(name: String, pages: [Int])] = []
            for rawSegment in segments {
                let seg = rawSegment.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !seg.isEmpty else { continue }
                let pages = PDFPageRangeParser.parse(seg, totalPages: totalPages)
                guard !pages.isEmpty else { continue }
                let sanitizedSeg = seg.replacingOccurrences(of: " ", with: "")
                let name = "\(baseName)_第\(sanitizedSeg)页"
                groups.append((name, pages))
            }
            guard !groups.isEmpty else {
                throw ConversionError.invalidOptions("未指定有效的拆分页码范围")
            }
            pageGroups = groups
        }

        var createdURLs: [URL] = []
        let groupCount = Double(pageGroups.count)
        for (index, group) in pageGroups.enumerated() {
            let newDoc = PDFDocument()
            for pageNumber in group.pages {
                if let page = sourceDoc.page(at: pageNumber - 1) {
                    newDoc.insert(page, at: newDoc.pageCount)
                }
            }
            guard newDoc.pageCount > 0 else { continue }
            var targetURL = destinationDirectory
                .appendingPathComponent(group.name)
                .appendingPathExtension("pdf")
            if fileManager.fileExists(atPath: targetURL.path) {
                var counter = 1
                repeat {
                    targetURL = destinationDirectory
                        .appendingPathComponent("\(group.name) (\(counter))")
                        .appendingPathExtension("pdf")
                    counter += 1
                } while fileManager.fileExists(atPath: targetURL.path)
            }
            guard newDoc.write(to: targetURL) else {
                throw ConversionError.processFailed("保存拆分 PDF 失败：\(targetURL.lastPathComponent)")
            }
            createdURLs.append(targetURL)
            progress?(Double(index + 1) / groupCount * 0.95)
        }
        progress?(1.0)
        return createdURLs
    }

    public static func reorderAndRotatePDF(
        pdfURL: URL,
        pageSpecs: [PDFPageSpec],
        destinationURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> URL {
        guard let sourceDoc = PDFDocument(url: pdfURL), sourceDoc.pageCount > 0 else {
            throw ConversionError.unsupportedInput(pdfURL)
        }
        let activeSpecs = pageSpecs.filter(\.isIncluded)
        guard !activeSpecs.isEmpty else {
            throw ConversionError.invalidOptions("必须保留至少一页")
        }
        let fileManager = FileManager.default
        let tempURL = FileSafety.temporaryURL(for: destinationURL, jobID: UUID())
        try? fileManager.removeItem(at: tempURL)
        try fileManager.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let newDoc = PDFDocument()
        let total = Double(activeSpecs.count)
        for (index, spec) in activeSpecs.enumerated() {
            let sourceIndex = spec.originalPageIndex - 1
            guard sourceIndex >= 0, sourceIndex < sourceDoc.pageCount,
                  let page = sourceDoc.page(at: sourceIndex) else {
                continue
            }
            let originalRotation = page.rotation
            let finalRotation = (originalRotation + spec.rotationAngle) % 360
            let normalizedRotation = finalRotation < 0 ? finalRotation + 360 : finalRotation
            page.rotation = normalizedRotation
            newDoc.insert(page, at: newDoc.pageCount)
            progress?(Double(index + 1) / total * 0.9)
        }

        guard newDoc.write(to: tempURL) else {
            try? fileManager.removeItem(at: tempURL)
            throw ConversionError.processFailed("重排 PDF 写入失败")
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: tempURL, to: destinationURL)
        progress?(1.0)
        return destinationURL
    }

    public static func exportPDFPagesToImages(
        pdfURL: URL,
        format: FormatID,
        options: ConversionOptions,
        destinationDirectory: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> [URL] {
        guard let sourceDoc = CGPDFDocument(pdfURL as CFURL), sourceDoc.numberOfPages > 0 else {
            throw ConversionError.unsupportedInput(pdfURL)
        }
        let totalPages = sourceDoc.numberOfPages
        let pagesToExport: [Int]
        switch options.pdfPageExportScope {
        case .allPages:
            pagesToExport = Array(1...totalPages)
        case .firstPage:
            pagesToExport = [1]
        case .customRange:
            let parsed = PDFPageRangeParser.parse(options.pdfCustomPageRange ?? "", totalPages: totalPages)
            pagesToExport = parsed.isEmpty ? [1] : parsed
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let baseName = pdfURL.deletingPathExtension().lastPathComponent
        let digits = max(2, String(totalPages).count)
        var exportedURLs: [URL] = []
        let countDouble = Double(pagesToExport.count)

        for (index, pageNum) in pagesToExport.enumerated() {
            guard let page = sourceDoc.page(at: pageNum) else { continue }
            let pageBox = page.getBoxRect(.mediaBox)
            let scale = CGFloat(max(1, min(options.pdfRenderScale, 3)))
            let targetSize = CGSize(
                width: max(1, (pageBox.width * scale).rounded()),
                height: max(1, (pageBox.height * scale).rounded())
            )
            let colorSpace = ImageRenderer.outputColorSpace(for: options.imageColorProfile)
            guard let context = CGContext(
                data: nil,
                width: Int(targetSize.width),
                height: Int(targetSize.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { continue }

            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: targetSize))
            let targetRect = CGRect(origin: .zero, size: targetSize)
            context.concatenate(page.getDrawingTransform(
                .mediaBox,
                rect: targetRect,
                rotate: Int32(options.rotationDegrees),
                preserveAspectRatio: true
            ))
            context.drawPDFPage(page)
            guard var image = context.makeImage() else { continue }
            if options.trimBorders {
                image = ImageRenderer.trimBorders(in: image)
            }

            let pageSuffix = pagesToExport.count == 1 && totalPages == 1
                ? ""
                : String(format: "_%0\(digits)d", pageNum)
            var fileURL = destinationDirectory
                .appendingPathComponent("\(baseName)\(pageSuffix)")
                .appendingPathExtension(format.fileExtension)

            if fileManager.fileExists(atPath: fileURL.path) {
                var counter = 1
                repeat {
                    fileURL = destinationDirectory
                        .appendingPathComponent("\(baseName)\(pageSuffix) (\(counter))")
                        .appendingPathExtension(format.fileExtension)
                    counter += 1
                } while fileManager.fileExists(atPath: fileURL.path)
            }

            try ImageRenderer.write(
                image: image,
                sourceProperties: [:],
                to: fileURL,
                format: format,
                options: options
            )
            exportedURLs.append(fileURL)
            progress?(Double(index + 1) / countDouble * 0.95)
        }
        progress?(1.0)
        return exportedURLs
    }

    private static func drawImageOnPage(
        _ image: CGImage,
        pageRect: CGRect,
        drawRect: CGRect,
        colorSpace: CGColorSpace
    ) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: Int(pageRect.width),
            height: Int(pageRect.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(pageRect)
        context.draw(image, in: drawRect)
        return context.makeImage()
    }
}
