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
            url: "https://github.com/EncoreKit/ios-sdk/releases/download/v1.4.23/Encore.xcframework.zip",
            checksum: "51714c61e7781af009a09f477edc64fffdb785b6c502c6156756305de56958de"
        )
    ]
)
