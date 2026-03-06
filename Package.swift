// swift-tools-version:5.9
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
    targets: [
        .target(
            name: "Encore",
            path: ".",
            sources: ["Sources/Encore", "Vendor/OpenAPIRuntime", "Vendor/HTTPTypes"]
        ),
    ]
)
