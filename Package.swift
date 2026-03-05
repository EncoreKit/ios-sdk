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
            url: "https://github.com/EncoreKit/ios-sdk/releases/download/v1.4.22/Encore.xcframework.zip",
            checksum: "f5614dde676f12da24286ef98ecf59349f2d917e5ec4816ff2e6e0f5d18e2054"
        )
    ]
)
