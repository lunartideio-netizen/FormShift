import Foundation
import XCTest
@testable import FormShiftCore

final class FormatIDTests: XCTestCase {
    func testFileExtensionsAndAliases() {
        XCTAssertEqual(FormatID.jpeg.fileExtension, "jpg")
        XCTAssertEqual(FormatID.from(url: URL(fileURLWithPath: "/tmp/photo.JPG")), .jpeg)
        XCTAssertEqual(FormatID.from(url: URL(fileURLWithPath: "/tmp/photo.heif")), .heic)
        XCTAssertEqual(FormatID.from(url: URL(fileURLWithPath: "/tmp/movie.MP4")), .mp4)
        XCTAssertNil(FormatID.from(url: URL(fileURLWithPath: "/tmp/archive.zip")))
    }

    func testEveryFormatHasTheExpectedCategory() {
        let imageFormats: Set<FormatID> = [.jpeg, .png, .heic, .tiff, .bmp, .webp, .avif]
        let videoFormats: Set<FormatID> = [.mp4, .mov, .mkv, .webm]
        let audioFormats: Set<FormatID> = [.mp3, .m4a, .aac, .wav, .aiff, .flac, .alac, .ogg, .opus]

        for format in FormatID.allCases {
            switch format.category {
            case .image:
                XCTAssertTrue(imageFormats.contains(format))
            case .video:
                XCTAssertTrue(videoFormats.contains(format))
            case .audio:
                XCTAssertTrue(audioFormats.contains(format))
            case .animatedImage:
                XCTAssertEqual(format, .gif)
            case .pdf:
                XCTAssertEqual(format, .pdf)
            }
        }
    }

    func testFormatIDCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(FormatID.allCases)
        let decoded = try JSONDecoder().decode([FormatID].self, from: encoded)
        XCTAssertEqual(decoded, FormatID.allCases)
    }
}
