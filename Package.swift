// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "CritiqueAI2", platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "CritiqueCore", targets: ["CritiqueCore"]),
               .executable(name: "critique-coach-fixtures", targets: ["CoachFixtureExporter"])],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(name: "CritiqueCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "CoachFixtureExporter", dependencies: ["CritiqueCore"], path: "Tools/CoachFixtureExporter"),
        .testTarget(name: "CritiqueCoreTests", dependencies: ["CritiqueCore"])
    ])
