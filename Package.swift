// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AutoTimerMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AutoTimerMac", targets: ["AutoTimerMac"])
    ],
    targets: [
        .executableTarget(
            name: "AutoTimerMac",
            path: "Sources/AutoTimerMac"
        )
    ]
)
