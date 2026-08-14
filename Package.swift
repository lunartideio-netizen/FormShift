// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FormShift",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "FormShift", targets: ["FormShiftApp"]),
        .library(name: "FormShiftCore", targets: ["FormShiftCore"]),
        .library(name: "FormShiftEngines", targets: ["FormShiftEngines"]),
        .library(name: "FormShiftPersistence", targets: ["FormShiftPersistence"])
    ],
    targets: [
        .target(name: "FormShiftCore"),
        .target(
            name: "FormShiftEngines",
            dependencies: ["FormShiftCore"]
        ),
        .target(
            name: "FormShiftPersistence",
            dependencies: ["FormShiftCore"]
        ),
        .executableTarget(
            name: "FormShiftApp",
            dependencies: ["FormShiftCore", "FormShiftEngines", "FormShiftPersistence"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "FormShiftSmoke",
            dependencies: ["FormShiftCore", "FormShiftEngines", "FormShiftPersistence"]
        ),
        .testTarget(
            name: "FormShiftCoreTests",
            dependencies: ["FormShiftCore"]
        ),
        .testTarget(
            name: "FormShiftEnginesTests",
            dependencies: ["FormShiftCore", "FormShiftEngines"]
        ),
        .testTarget(
            name: "FormShiftPersistenceTests",
            dependencies: ["FormShiftCore", "FormShiftPersistence"]
        )
    ],
    swiftLanguageModes: [.v6]
)
