// swift-tools-version:5.9
// Source distribution Package.swift — must mirror root Package.swift minus dev-only deps and test targets
import PackageDescription

let package = Package(
    name: "Encore",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(
            name: "Encore",
            targets: ["Encore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "Encore",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            path: "Sources/Encore",
            swiftSettings: [
                .enableExperimentalFeature("AccessLevelOnImport"),
            ]
        ),
    ]
)
