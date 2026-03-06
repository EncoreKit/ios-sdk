// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Encore",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "Encore", targets: ["Encore"])
    ],
    targets: [
        .binaryTarget(
            name: "Encore",
            url: "https://github.com/EncoreKit/ios-sdk/releases/download/v1.4.24/Encore.xcframework.zip",
            checksum: "eb4426218447d60635a841921859903deddc3b0d97d145e5c4b56dd9554cedb5"
        )
    ]
)
