import Foundation
import XCTest
@testable import FormShiftCore

final class CodableTests: XCTestCase {
    func testConversionOptionsJSONRoundTripPreservesEverySetting() throws {
        let original = ConversionOptions(
            quality: 0.72,
            width: 1920,
            height: 1080,
            preserveAspectRatio: false,
            imageSizingMode: .fill,
            trimBorders: true,
            crop: CropRect(x: 10, y: 20, width: 800, height: 600),
            rotationDegrees: 90,
            imageColorProfile: .displayP3,
            pdfRenderScale: 3,
            pdfPageExportScope: .customRange,
            pdfCustomPageRange: "1-3, 5",
            videoCodec: .hevc,
            preferHardwareEncoding: false,
            videoBitrateKbps: 8_000,
            audioBitrateKbps: 256,
            frameRate: 23.976,
            sampleRate: 48_000,
            audioChannels: 2,
            trimStartSeconds: 1.25,
            trimEndSeconds: 9.75,
            normalizeAudio: true,
            removeAudio: false,
            metadataPolicy: .remove
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConversionOptions.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testLegacyConversionOptionsDefaultToPreservingAspectRatio() throws {
        let data = Data(#"{"quality":0.85,"width":1920,"height":1080}"#.utf8)
        let decoded = try JSONDecoder().decode(ConversionOptions.self, from: data)

        XCTAssertTrue(decoded.preserveAspectRatio)
        XCTAssertEqual(decoded.imageSizingMode, .fit)
        XCTAssertFalse(decoded.trimBorders)
        XCTAssertEqual(decoded.imageColorProfile, .automatic)
        XCTAssertEqual(decoded.pdfRenderScale, 2)
        XCTAssertEqual(decoded.pdfPageExportScope, .allPages)
        XCTAssertNil(decoded.pdfCustomPageRange)
    }

    func testConversionJobJSONRoundTripPreservesState() throws {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let completed = created.addingTimeInterval(12)
        let job = ConversionJob(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            sourceURL: URL(fileURLWithPath: "/tmp/源文件.mov"),
            sourceFormat: .mov,
            outputFormat: .mp4,
            options: ConversionOptions(videoCodec: .h264, removeAudio: true),
            status: .succeeded,
            progress: 1,
            statusDetail: "完成",
            destinationURL: URL(fileURLWithPath: "/tmp/源文件.mp4"),
            createdAt: created,
            completedAt: completed
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(job)
        let decoded = try decoder.decode(ConversionJob.self, from: data)

        XCTAssertEqual(decoded, job)
    }

    func testProgressClampsFractionToValidRange() {
        XCTAssertEqual(ConversionProgress(fraction: -0.5).fraction, 0)
        XCTAssertEqual(ConversionProgress(fraction: 0.4).fraction, 0.4)
        XCTAssertEqual(ConversionProgress(fraction: 2).fraction, 1)
    }

    func testPDFPageRangeParser() {
        XCTAssertEqual(PDFPageRangeParser.parse("1-3, 5, 8", totalPages: 10), [1, 2, 3, 5, 8])
        XCTAssertEqual(PDFPageRangeParser.parse("", totalPages: 10), [])
        XCTAssertEqual(PDFPageRangeParser.parse("10-15", totalPages: 12), [10, 11, 12])
        XCTAssertEqual(PDFPageRangeParser.parse("3-1", totalPages: 5), [1, 2, 3])
    }

    func testPDFModelsRoundTrip() throws {
        let spec = PDFPageSpec(originalPageIndex: 3, rotationAngle: 90, isIncluded: true)
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(PDFPageSpec.self, from: data)
        XCTAssertEqual(decoded, spec)
    }
}
