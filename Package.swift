// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "itstime",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "itstime", targets: ["itstime"])
    ],
    targets: [
        .executableTarget(
            name: "itstime",
            path: "Sources/itstime",
            resources: [.process("BrandAssets")]
        ),
        .testTarget(
            name: "ItsTimeTests",
            dependencies: ["itstime"],
            path: "Tests/ItsTimeTests"
        )
    ]
)
