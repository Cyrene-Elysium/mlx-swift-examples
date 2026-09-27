// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "download-probe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.11.0"),
    ],
    targets: [
        .executableTarget(
            name: "probe",
            dependencies: [
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ],
            path: "Sources/probe")
    ]
)
