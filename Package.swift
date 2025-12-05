// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "SocketRocket",
    platforms: [.iOS(.v9)],
    products: [
        .library(
            name: "SocketRocket",
            targets: ["SocketRocket"]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "SocketRocket",
            path: "SocketRocket",
            exclude: ["Resources"], // Исключите ненужные файлы или директории
            sources: [".", "Internal"], // Указание исходных файлов
            publicHeadersPath: "include", // Все публичные заголовки должны быть перемещены в 'include'
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("Internal"),
                .headerSearchPath("Internal/Delegate"),
                .headerSearchPath("Internal/IOConsumer"),
                .headerSearchPath("Internal/Proxy"),
                .headerSearchPath("Internal/RunLoop"),                
                .headerSearchPath("Internal/Security"),
                .headerSearchPath("Internal/Utilities")
            ],
            linkerSettings: [
                .linkedFramework("CFNetwork", .when(platforms: [.iOS, .tvOS])),
                .linkedFramework("Security"),
                .linkedFramework("CoreServices", .when(platforms: [.macOS])),
                .linkedLibrary("icucore")
            ]
        )
    ]
)
