import XCTest
@testable import FormShiftEngines

final class EngineSmokeTests: XCTestCase {
    func testEngineModuleLoads() {
        _ = FormShiftEnginesModule.self
    }
}
