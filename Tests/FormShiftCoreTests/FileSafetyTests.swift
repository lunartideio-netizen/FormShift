import Foundation
import XCTest
@testable import FormShiftCore

final class FileSafetyTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FormShiftTests-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testDestinationUsesSourceDirectoryAndRequestedExtension() {
        let source = temporaryDirectory.appendingPathComponent("clip.mov")
        let destination = FileSafety.destinationURL(for: source, outputFormat: .mp4)

        XCTAssertEqual(destination, temporaryDirectory.appendingPathComponent("clip.mp4"))
    }

    func testDestinationNeverOverwritesSourceForSameFormat() throws {
        let source = temporaryDirectory.appendingPathComponent("image.png")
        try Data([0x00]).write(to: source)

        let destination = FileSafety.destinationURL(for: source, outputFormat: .png)

        XCTAssertEqual(destination.lastPathComponent, "image 1.png")
        XCTAssertNotEqual(destination.standardizedFileURL, source.standardizedFileURL)
    }

    func testDestinationIncrementsPastExistingFiles() throws {
        let source = temporaryDirectory.appendingPathComponent("image.heic")
        let first = temporaryDirectory.appendingPathComponent("image.jpg")
        let second = temporaryDirectory.appendingPathComponent("image 1.jpg")
        try Data([0x00]).write(to: first)
        try Data([0x00]).write(to: second)

        let destination = FileSafety.destinationURL(for: source, outputFormat: .jpeg)

        XCTAssertEqual(destination.lastPathComponent, "image 2.jpg")
    }

    func testDestinationCanUseExplicitDirectory() {
        let source = temporaryDirectory.appendingPathComponent("input/photo.png")
        let outputDirectory = temporaryDirectory.appendingPathComponent("exports", isDirectory: true)

        let destination = FileSafety.destinationURL(
            for: source,
            outputFormat: .webp,
            directory: outputDirectory
        )

        XCTAssertEqual(destination, outputDirectory.appendingPathComponent("photo.webp"))
    }

    func testTemporaryURLIsHiddenUniqueAndKeepsDestinationExtension() {
        let destination = temporaryDirectory.appendingPathComponent("movie.mp4")
        let jobID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        let temporary = FileSafety.temporaryURL(for: destination, jobID: jobID)

        XCTAssertEqual(temporary.lastPathComponent, ".formshift-11111111-2222-3333-4444-555555555555.mp4")
        XCTAssertEqual(temporary.deletingLastPathComponent(), temporaryDirectory)
    }
}
