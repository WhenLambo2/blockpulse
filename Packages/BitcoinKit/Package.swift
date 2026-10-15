// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BitcoinKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "BitcoinKit", targets: ["BitcoinKit"])],
    targets: [
        .target(name: "BitcoinKit"),
        .testTarget(
            name: "BitcoinKitTests",
            dependencies: ["BitcoinKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
