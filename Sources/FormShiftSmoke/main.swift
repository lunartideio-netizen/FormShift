import CoreGraphics
import Foundation
import FormShiftCore
import FormShiftEngines
import FormShiftPersistence
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum SmokeFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): message
        }
    }
}

@main
struct FormShiftSmoke {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FormShiftSmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("bordered.png")
        try makeBorderedImage(at: source)
        try await testSmartTrim(source: source, root: root)
        try await testFill(source: source, root: root)
        try await testMultipleOutputs(source: source, root: root)
        try await testPDFScale(root: root)
        try await testPersistence(source: source, root: root)
        try await testPDFWorkbenchFeatures(root: root)
        try await testFrameWorkbenchFeatures(root: root)
        try await testPresetImportExport(root: root)
        try await testDocumentWorkbenchFeatures(root: root)
        print("FormShift smoke tests passed")
    }

    private static func testSmartTrim(source: URL, root: URL) async throws {
        let output = root.appendingPathComponent("trimmed.png")
        let engine = ImageIOEngine()
        let descriptor = try await engine.probe(url: source)
        let options = ConversionOptions(trimBorders: true, imageColorProfile: .sRGB)
        let plan = try engine.makePlan(
            jobID: UUID(), source: descriptor, output: .png, destination: output, options: options
        )
        _ = try await engine.run(plan: plan) { _ in }
        let size = try imageSize(at: output)
        try require(size.width >= 590 && size.width <= 620, "smart trim width was \(size.width)")
        try require(size.height >= 390 && size.height <= 420, "smart trim height was \(size.height)")
    }

    private static func testFill(source: URL, root: URL) async throws {
        let output = root.appendingPathComponent("filled.jpg")
        let engine = ImageIOEngine()
        let descriptor = try await engine.probe(url: source)
        let options = ConversionOptions(
            quality: 0.9,
            width: 300,
            height: 300,
            imageSizingMode: .fill,
            imageColorProfile: .displayP3
        )
        let plan = try engine.makePlan(
            jobID: UUID(), source: descriptor, output: .jpeg, destination: output, options: options
        )
        _ = try await engine.run(plan: plan) { _ in }
        let size = try imageSize(at: output)
        try require(size.width == 300 && size.height == 300, "fill output was \(size.width)x\(size.height)")
        guard let image = CGImageSourceCreateImageAtIndex(
            CGImageSourceCreateWithURL(output as CFURL, nil)!, 0, nil
        ) else {
            throw SmokeFailure.failed("cannot read fill output")
        }
        try require(image.colorSpace?.name == CGColorSpace.displayP3, "Display P3 profile was not preserved")
    }

    private static func testMultipleOutputs(source: URL, root: URL) async throws {
        let outputDirectory = root.appendingPathComponent("multi-output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let registry = await DefaultEngineRegistryFactory.makeRegistry()
        let queue = ConversionQueue(registry: registry, outputDirectory: outputDirectory)
        let jobs = [FormatID.jpeg, .pdf].map { format in
            ConversionJob(
                sourceURL: source,
                sourceFormat: .png,
                outputFormat: format,
                options: ConversionOptions(quality: 0.9)
            )
        }
        await queue.enqueue(jobs: jobs)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(8))
        var snapshot: [ConversionJob] = []
        while clock.now < deadline {
            snapshot = await queue.snapshot()
            if snapshot.count == 2, snapshot.allSatisfy({ $0.status == .succeeded }) {
                break
            }
            if snapshot.contains(where: { $0.status == .failed || $0.status == .cancelled }) {
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        try require(snapshot.count == 2, "multi-output queue did not create two jobs")
        try require(
            snapshot.allSatisfy { $0.status == .succeeded },
            "multi-output queue failed: \(snapshot.compactMap(\.statusDetail).joined(separator: "; "))"
        )
        let extensions = Set(snapshot.compactMap { $0.destinationURL?.pathExtension.lowercased() })
        try require(extensions == Set(["jpg", "pdf"]), "multi-output formats were \(extensions)")
        try require(
            snapshot.allSatisfy { job in
                job.destinationURL.map { FileManager.default.fileExists(atPath: $0.path) } == true
            },
            "multi-output result file was missing"
        )
    }

    private static func testPDFScale(root: URL) async throws {
        let source = root.appendingPathComponent("sample.pdf")
        try makePDF(at: source)
        let engine = PDFEngine()
        let descriptor = try await engine.probe(url: source)
        var sizes: [Int: CGSize] = [:]
        for scale in [1, 3] {
            let output = root.appendingPathComponent("pdf-\(scale)x.png")
            let options = ConversionOptions(pdfRenderScale: scale)
            let plan = try engine.makePlan(
                jobID: UUID(), source: descriptor, output: .png, destination: output, options: options
            )
            _ = try await engine.run(plan: plan) { _ in }
            sizes[scale] = try imageSize(at: output)
        }
        guard let standard = sizes[1], let high = sizes[3] else {
            throw SmokeFailure.failed("PDF scale outputs are missing")
        }
        try require(high.width == standard.width * 3, "PDF 3x width did not scale")
        try require(high.height == standard.height * 3, "PDF 3x height did not scale")
    }

    private static func testPersistence(source: URL, root: URL) async throws {
        let store = root.appendingPathComponent("History.json")
        let persistence = try PersistenceController(storeURL: store)
        var job = ConversionJob(
            sourceURL: source,
            sourceFormat: .png,
            outputFormat: .jpeg,
            options: ConversionOptions(trimBorders: true),
            status: .running
        )
        try await persistence.upsert(job: job)
        try await persistence.markInFlightJobsInterrupted()
        let records = await persistence.recentJobs()
        try require(records.count == 1, "history record was not saved")
        try require(records[0].status == JobStatus.interrupted.rawValue, "running job was not interrupted")
        try require(records[0].options?.trimBorders == true, "conversion options were not restored")
        try require(
            records[0].resolvedSourceURL()?.resolvingSymlinksInPath().path
                == source.resolvingSymlinksInPath().path,
            "source URL was not restored"
        )

        job.status = .succeeded
        job.destinationURL = root.appendingPathComponent("result.jpg")
        try await persistence.upsert(job: job)
        let updated = await persistence.recentJobs()
        try require(updated[0].destinationPath == job.destinationURL?.path, "result path was not persisted")
    }

    private static func testPDFWorkbenchFeatures(root: URL) async throws {
        let testDir = root.appendingPathComponent("pdf-workbench", isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        // 1. Page Range Parser Test
        let parsed = PDFPageRangeParser.parse(" 1-3, 5, 8-10 , 2 ", totalPages: 12)
        try require(parsed == [1, 2, 3, 5, 8, 9, 10], "Page range parser failed: \(parsed)")

        // 2. Multi-image to multi-page PDF
        var imgURLs: [URL] = []
        for i in 1...3 {
            let imgURL = testDir.appendingPathComponent("img_\(i).png")
            try makeBorderedImage(at: imgURL)
            imgURLs.append(imgURL)
        }
        let multiPDFURL = testDir.appendingPathComponent("from_images.pdf")
        let createdPDF = try PDFWorkbenchEngine.createPDF(
            fromImages: imgURLs,
            destinationURL: multiPDFURL,
            options: PDFImageMergeOptions(pageSizePreset: .a4Portrait, marginPoints: 18)
        )
        guard let docFromImages = PDFDocument(url: createdPDF) else {
            throw SmokeFailure.failed("Cannot open created multi-page PDF")
        }
        try require(docFromImages.pageCount == 3, "Multi-image PDF page count was \(docFromImages.pageCount), expected 3")

        // 3. PDF Merge Test
        let pdfA = testDir.appendingPathComponent("docA.pdf")
        let pdfB = testDir.appendingPathComponent("docB.pdf")
        try makeMultiPagePDF(at: pdfA, pageCount: 2)
        try makeMultiPagePDF(at: pdfB, pageCount: 3)
        let mergedPDFURL = testDir.appendingPathComponent("merged.pdf")
        let mergedResult = try PDFWorkbenchEngine.mergePDFs(pdfURLs: [pdfA, pdfB], destinationURL: mergedPDFURL)
        guard let mergedDoc = PDFDocument(url: mergedResult) else {
            throw SmokeFailure.failed("Cannot open merged PDF")
        }
        try require(mergedDoc.pageCount == 5, "Merged PDF page count was \(mergedDoc.pageCount), expected 5")

        // 4. PDF Split Test
        let splitDir = testDir.appendingPathComponent("split_out", isDirectory: true)
        let splitEach = try PDFWorkbenchEngine.splitPDF(pdfURL: mergedPDFURL, destinationDirectory: splitDir, strategy: .eachPage)
        try require(splitEach.count == 5, "Split each page count was \(splitEach.count), expected 5")

        let splitChunk = try PDFWorkbenchEngine.splitPDF(pdfURL: mergedPDFURL, destinationDirectory: splitDir, strategy: .fixedPageCount(2))
        try require(splitChunk.count == 3, "Split fixed page count was \(splitChunk.count), expected 3")

        let splitRange = try PDFWorkbenchEngine.splitPDF(pdfURL: mergedPDFURL, destinationDirectory: splitDir, strategy: .pageRanges("1-2, 3-5"))
        try require(splitRange.count == 2, "Split ranges count was \(splitRange.count), expected 2")

        // 5. PDF Reorder and Rotate Test
        let reorderDest = testDir.appendingPathComponent("reordered.pdf")
        let specs: [PDFPageSpec] = [
            PDFPageSpec(originalPageIndex: 5, rotationAngle: 90, isIncluded: true),
            PDFPageSpec(originalPageIndex: 3, rotationAngle: 0, isIncluded: false), // exclude
            PDFPageSpec(originalPageIndex: 1, rotationAngle: 180, isIncluded: true)
        ]
        let reorderedResult = try PDFWorkbenchEngine.reorderAndRotatePDF(pdfURL: mergedPDFURL, pageSpecs: specs, destinationURL: reorderDest)
        guard let reorderedDoc = PDFDocument(url: reorderedResult) else {
            throw SmokeFailure.failed("Cannot open reordered PDF")
        }
        try require(reorderedDoc.pageCount == 2, "Reordered PDF page count was \(reorderedDoc.pageCount), expected 2")
        try require(reorderedDoc.page(at: 0)?.rotation == 90, "Page 1 rotation was \(String(describing: reorderedDoc.page(at: 0)?.rotation)), expected 90")
        try require(reorderedDoc.page(at: 1)?.rotation == 180, "Page 2 rotation was \(String(describing: reorderedDoc.page(at: 1)?.rotation)), expected 180")

        // 6. PDF Batch Image Export Test
        let imagesDir = testDir.appendingPathComponent("extracted_images", isDirectory: true)
        let exportOptions = ConversionOptions(pdfRenderScale: 2, pdfPageExportScope: .allPages)
        let extractedImages = try PDFWorkbenchEngine.exportPDFPagesToImages(
            pdfURL: mergedPDFURL,
            format: .png,
            options: exportOptions,
            destinationDirectory: imagesDir
        )
        try require(extractedImages.count == 5, "Extracted images count was \(extractedImages.count), expected 5")
        for img in extractedImages {
            let sz = try imageSize(at: img)
            try require(sz.width > 0 && sz.height > 0, "Extracted image \(img.lastPathComponent) had invalid size")
        }

        // 7. Test PDFEngine multi-page export through engine run
        let engine = PDFEngine()
        let descriptor = try await engine.probe(url: mergedPDFURL)
        let queueExportDest = testDir.appendingPathComponent("queue_export.png")
        let enginePlan = try engine.makePlan(
            jobID: UUID(),
            source: descriptor,
            output: .png,
            destination: queueExportDest,
            options: ConversionOptions(pdfRenderScale: 1, pdfPageExportScope: .customRange, pdfCustomPageRange: "1-2")
        )
        _ = try await engine.run(plan: enginePlan) { _ in }
        try require(FileManager.default.fileExists(atPath: queueExportDest.path), "Queue export destination missing")
        let page2File = testDir.appendingPathComponent("queue_export_02.png")
        try require(FileManager.default.fileExists(atPath: page2File.path), "Queue export page 2 file missing")
    }

    private static func testFrameWorkbenchFeatures(root: URL) async throws {
        let testDir = root.appendingPathComponent("frame-workbench", isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        // 1. Image Sequence to GIF Test
        var frames: [URL] = []
        for i in 1...3 {
            let fURL = testDir.appendingPathComponent("seq_\(i).png")
            try makeBorderedImage(at: fURL)
            frames.append(fURL)
        }
        let outputGIF = testDir.appendingPathComponent("created.gif")
        let gifResult = try FrameWorkbenchEngine.createGIF(
            imageURLs: frames,
            destinationURL: outputGIF,
            options: FrameSequenceOptions(frameRate: 10, loopCount: 0)
        )
        guard let gifSource = CGImageSourceCreateWithURL(gifResult as CFURL, nil) else {
            throw SmokeFailure.failed("Cannot open created GIF")
        }
        let frameCount = CGImageSourceGetCount(gifSource)
        try require(frameCount == 3, "Created GIF frame count was \(frameCount), expected 3")

        // 2. GIF Split Test
        let splitDir = testDir.appendingPathComponent("gif_frames", isDirectory: true)
        let extractedFrames = try FrameWorkbenchEngine.splitGIF(
            gifURL: outputGIF,
            destinationDirectory: splitDir,
            format: .png
        )
        try require(extractedFrames.count == 3, "Extracted GIF frames count was \(extractedFrames.count), expected 3")
        for f in extractedFrames {
            let sz = try imageSize(at: f)
            try require(sz.width > 0 && sz.height > 0, "Extracted frame \(f.lastPathComponent) had invalid size")
        }
    }

    private static func testPresetImportExport(root: URL) async throws {
        let presetFile = root.appendingPathComponent("test.formshiftpreset")
        let originalPresets = [
            Preset(id: UUID(), name: "测试高清", outputFormat: .jpeg, options: ConversionOptions(quality: 0.95, width: 3840)),
            Preset(id: UUID(), name: "测试缩略图", outputFormat: .png, options: ConversionOptions(quality: 0.8, width: 400))
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(originalPresets)
        try data.write(to: presetFile)

        let decodedData = try Data(contentsOf: presetFile)
        let decoded = try JSONDecoder().decode([Preset].self, from: decodedData)
        try require(decoded.count == 2, "Decoded presets count was \(decoded.count), expected 2")
        try require(decoded[0].name == "测试高清", "Decoded preset name mismatch")
    }

    private static func testDocumentWorkbenchFeatures(root: URL) async throws {
        let testDir = root.appendingPathComponent("doc-workbench", isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        // 1. Text / RTF to PDF
        let textFile = testDir.appendingPathComponent("sample.txt")
        try "FormShift 本地文档排版测试\n这是第二行测试文字。".write(to: textFile, atomically: true, encoding: .utf8)
        let docPDF = testDir.appendingPathComponent("from_text.pdf")
        _ = try DocumentWorkbenchEngine.convertOfficeToPDF(sourceURL: textFile, destinationURL: docPDF)
        guard let pdfDoc = PDFDocument(url: docPDF) else {
            throw SmokeFailure.failed("Cannot open converted PDF from text")
        }
        try require(pdfDoc.pageCount >= 1, "Text to PDF page count was 0")

        // 2. PDF to Word (.docx)
        let outWord = testDir.appendingPathComponent("converted.docx")
        _ = try DocumentWorkbenchEngine.convertPDFToWord(pdfURL: docPDF, destinationURL: outWord)
        guard FileManager.default.fileExists(atPath: outWord.path) else {
            throw SmokeFailure.failed("DOCX output was not created")
        }
        let wordData = try Data(contentsOf: outWord)
        try require(wordData.count > 100, "DOCX file was too small: \(wordData.count) bytes")
        try require(wordData.starts(with: [0x50, 0x4B, 0x03, 0x04]), "DOCX is not a valid zip archive")

        // 3. PDF to Excel (.xlsx and .csv)
        let outXlsx = testDir.appendingPathComponent("converted.xlsx")
        _ = try DocumentWorkbenchEngine.convertPDFToExcel(pdfURL: docPDF, destinationURL: outXlsx, asCSV: false)
        guard FileManager.default.fileExists(atPath: outXlsx.path) else {
            throw SmokeFailure.failed("XLSX output was not created")
        }
        let xlsxData = try Data(contentsOf: outXlsx)
        try require(xlsxData.starts(with: [0x50, 0x4B, 0x03, 0x04]), "XLSX is not a valid zip archive")

        let outCSV = testDir.appendingPathComponent("converted.csv")
        _ = try DocumentWorkbenchEngine.convertPDFToExcel(pdfURL: docPDF, destinationURL: outCSV, asCSV: true)
        let csvText = try String(contentsOf: outCSV, encoding: .utf8)
        try require(!csvText.isEmpty, "CSV output was empty")

        // 4. PDF to Text
        let outTxt = testDir.appendingPathComponent("converted.txt")
        _ = try DocumentWorkbenchEngine.convertPDFToText(pdfURL: docPDF, destinationURL: outTxt)
        let extractedText = try String(contentsOf: outTxt, encoding: .utf8)
        try require(extractedText.contains("FormShift"), "Extracted text missing expected content")
    }

    private static func makeBorderedImage(at url: URL) throws {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: 1200,
            height: 800,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw SmokeFailure.failed("cannot create image context") }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        context.setFillColor(CGColor(gray: 0.05, alpha: 1))
        context.fill(CGRect(x: 300, y: 200, width: 600, height: 400))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
              ) else { throw SmokeFailure.failed("cannot create PNG") }
        CGImageDestinationAddImage(destination, image, nil)
        try require(CGImageDestinationFinalize(destination), "cannot finalize PNG")
    }

    private static func makePDF(at url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 200, height: 100)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw SmokeFailure.failed("cannot create PDF")
        }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(box)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 20, y: 20, width: 160, height: 60))
        context.endPDFPage()
        context.closePDF()
    }

    private static func makeMultiPagePDF(at url: URL, pageCount: Int) throws {
        var box = CGRect(x: 0, y: 0, width: 200, height: 100)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw SmokeFailure.failed("cannot create PDF")
        }
        for i in 1...pageCount {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(box)
            context.setFillColor(CGColor(red: CGFloat(i) / CGFloat(pageCount), green: 0.2, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 20, y: 20, width: 160, height: 60))
            context.endPDFPage()
        }
        context.closePDF()
    }

    private static func imageSize(at url: URL) throws -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue else {
            throw SmokeFailure.failed("cannot inspect \(url.lastPathComponent)")
        }
        return CGSize(width: width, height: height)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw SmokeFailure.failed(message) }
    }
}
