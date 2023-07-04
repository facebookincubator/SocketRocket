// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "SocketRocket",
    platforms: [
        .iOS(.v9),
        .macOS(.v10_10),
        .tvOS(.v9),
    ],
    products: [
        .library(
            name: "SocketRocket",
            targets: ["SocketRocket"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SocketRocket",
            path: "SocketRocket",
            cSettings: [
                .headerSearchPath("Internal/**"),
            ]),
    ]
)
