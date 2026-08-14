import CoreGraphics
import Foundation
import FormShiftCore
import FormShiftEngines
import FormShiftPersistence
import ImageIO
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
