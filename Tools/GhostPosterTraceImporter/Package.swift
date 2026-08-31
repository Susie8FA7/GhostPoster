// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GhostPosterTraceImporter",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "GhostPosterTraceImportCore",
            targets: ["GhostPosterTraceImportCore"]
        ),
        .executable(
            name: "ghostposter-trace-import",
            targets: ["GhostPosterTraceImportCommand"]
        )
    ],
    targets: [
        .target(
            name: "GhostPosterTraceImportCore",
            linkerSettings: [.linkedFramework("Security")]
        ),
        .executableTarget(
            name: "GhostPosterTraceImportCommand",
            dependencies: ["GhostPosterTraceImportCore"]
        ),
        .testTarget(
            name: "GhostPosterTraceImportCoreTests",
            dependencies: ["GhostPosterTraceImportCore"]
        )
    ]
)
