// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ApplaudIQEmbed",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "ApplaudIQEmbed", targets: ["ApplaudIQEmbed"])
    ],
    targets: [
        .target(name: "ApplaudIQEmbed", path: "Sources/ApplaudIQEmbed"),
        // iOS-only package (imports UIKit/WebKit) — run via:
        //   xcodebuild test -scheme ApplaudIQEmbed -destination 'platform=iOS Simulator,name=iPhone 16'
        .testTarget(
            name: "ApplaudIQEmbedTests",
            dependencies: ["ApplaudIQEmbed"],
            path: "Tests/ApplaudIQEmbedTests"
        ),
    ]
)
