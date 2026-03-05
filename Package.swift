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
            url: "https://github.com/EncoreKit/ios-sdk/releases/download/v1.4.21/Encore.xcframework.zip",
            checksum: "36e1332034ca5c8ddff5e0ca9ba6ee1b45719f70dcfe95dd37e155eed768a52a"
        )
    ]
)
