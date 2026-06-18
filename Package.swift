// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ApplaudIQEmbed",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "ApplaudIQEmbed", targets: ["ApplaudIQEmbed"])
    ],
    targets: [
        .target(name: "ApplaudIQEmbed", path: "Sources/ApplaudIQEmbed")
    ]
)
