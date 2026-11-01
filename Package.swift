// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "gzyms",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/dduan/TOMLDecoder", from: "0.4.5"),
    ],
    targets: [
        .target(name: "GzymsCore", dependencies: [.product(name: "TOMLDecoder", package: "TOMLDecoder")]),
        .target(name: "GzymsUI", dependencies: ["GzymsCore"]),
        .executableTarget(name: "gzyms", dependencies: ["GzymsCore", "GzymsUI"]),
        .testTarget(name: "GzymsCoreTests", dependencies: ["GzymsCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "GzymsUITests", dependencies: ["GzymsUI"]),
    ]
)
