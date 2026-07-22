// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UnwindNative",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Unwind", targets: ["UnwindApp"])
    ],
    targets: [
        .executableTarget(
            name: "UnwindApp",
            path: "Sources/UnwindApp"
        )
    ]
)
