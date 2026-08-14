import Foundation
import XCTest
@testable import FormShiftCore
@testable import FormShiftPersistence

final class PersistenceControllerTests: XCTestCase {
    func testHistoryRestoresOptionsAndMarksRunningJobInterrupted() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FormShiftPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source.png")
        try Data([0]).write(to: source)
        let store = root.appendingPathComponent("History.json")
        let persistence = try PersistenceController(storeURL: store)
        let job = ConversionJob(
            sourceURL: source,
            sourceFormat: .png,
            outputFormat: .jpeg,
            options: ConversionOptions(imageSizingMode: .fill, trimBorders: true),
            status: .running
        )

        try await persistence.upsert(job: job)
        try await persistence.markInFlightJobsInterrupted()
        let records = await persistence.recentJobs()

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].status, JobStatus.interrupted.rawValue)
        XCTAssertEqual(records[0].options?.imageSizingMode, .fill)
        XCTAssertEqual(records[0].options?.trimBorders, true)
        XCTAssertEqual(
            records[0].resolvedSourceURL()?.resolvingSymlinksInPath().path,
            source.resolvingSymlinksInPath().path
        )
    }

    func testLegacyHistoryWithoutNewFieldsStillDecodes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FormShiftLegacyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("History.json")
        let json = #"{"jobs":[{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","sourceFileName":"old.png","outputFormat":"jpeg","status":"succeeded","createdAt":"2026-08-15T00:00:00Z"}],"presets":[]}"#
        try Data(json.utf8).write(to: store)

        let persistence = try PersistenceController(storeURL: store)
        let records = await persistence.recentJobs()
        XCTAssertEqual(records.first?.sourceFileName, "old.png")
        XCTAssertNil(records.first?.sourcePath)
    }
}
