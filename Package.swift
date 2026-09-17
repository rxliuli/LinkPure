// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LinkPureCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "LinkPureCore", targets: ["LinkPureCore"]),
    ],
    targets: [
        .target(
            name: "LinkPureCore",
            resources: [
                .copy("Resources/shared-rules.json"),
            ]
        ),
        .testTarget(
            name: "LinkPureCoreTests",
            dependencies: ["LinkPureCore"],
            resources: [
                .copy("Vectors"),
            ]
        ),
    ]
)
