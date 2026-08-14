import Foundation
import XCTest
@testable import FormShiftCore

final class EngineRegistryTests: XCTestCase {
    func testRegisterAndLookupByIdentifier() async throws {
        let registry = EngineRegistry()
        await registry.register(TestEngine(id: "images", capabilities: []))

        let engine = await registry.engine(id: "images")

        XCTAssertEqual(try XCTUnwrap(engine).id, "images")
    }

    func testLookupByConversionCapability() async throws {
        let capability = ConversionCapability(
            engineID: "images",
            input: .png,
            output: .jpeg,
            supportsResize: true
        )
        let registry = EngineRegistry()
        await registry.register(TestEngine(id: "images", capabilities: [capability]))

        let engine = await registry.engine(input: .png, output: .jpeg)

        XCTAssertEqual(try XCTUnwrap(engine).id, "images")
        let missing = await registry.engine(input: .pdf, output: .png)
        XCTAssertNil(missing)
    }

    func testCapabilitiesAreFilteredAndSortedByOutputName() async {
        let registry = EngineRegistry()
        await registry.register(TestEngine(id: "second", capabilities: [
            ConversionCapability(engineID: "second", input: .png, output: .webp),
            ConversionCapability(engineID: "second", input: .jpeg, output: .png)
        ]))
        await registry.register(TestEngine(id: "first", capabilities: [
            ConversionCapability(engineID: "first", input: .png, output: .avif),
            ConversionCapability(engineID: "first", input: .png, output: .jpeg)
        ]))

        let capabilities = await registry.capabilities(for: .png)

        XCTAssertEqual(capabilities.map(\.output), [.avif, .jpeg, .webp])
        XCTAssertTrue(capabilities.allSatisfy { $0.input == .png })
    }

    func testRegisteringSameIdentifierReplacesEngine() async throws {
        let registry = EngineRegistry()
        await registry.register(TestEngine(id: "images", capabilities: []))
        await registry.register(TestEngine(
            id: "images",
            capabilities: [ConversionCapability(engineID: "images", input: .png, output: .jpeg)]
        ))

        let engine = await registry.engine(id: "images")

        XCTAssertEqual(try XCTUnwrap(engine).capabilities.count, 1)
    }
}

private struct TestEngine: ConversionEngine {
    let id: String
    let capabilities: [ConversionCapability]

    func probe(url: URL) async throws -> MediaDescriptor {
        guard let format = FormatID.from(url: url) else {
            throw ConversionError.unsupportedInput(url)
        }
        return MediaDescriptor(url: url, format: format)
    }

    func validate(source: MediaDescriptor, output: FormatID, options: ConversionOptions) throws {}

    func makePlan(
        jobID: UUID,
        source: MediaDescriptor,
        output: FormatID,
        destination: URL,
        options: ConversionOptions
    ) throws -> ConversionPlan {
        ConversionPlan(
            jobID: jobID,
            engineID: id,
            source: source,
            outputFormat: output,
            temporaryURL: FileSafety.temporaryURL(for: destination, jobID: jobID),
            destinationURL: destination,
            options: options
        )
    }

    func run(
        plan: ConversionPlan,
        progress: @escaping @Sendable (ConversionProgress) -> Void
    ) async throws -> URL {
        progress(ConversionProgress(fraction: 1))
        return plan.destinationURL
    }

    func cancel(jobID: UUID) async {}
}
