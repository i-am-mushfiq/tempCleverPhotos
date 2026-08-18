// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AlbumCurator",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AlbumCurator",
            targets: ["AlbumCuratorApp"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "AlbumCuratorApp",
            dependencies: [],
            path: "Sources/AlbumCuratorApp"
        ),
        .testTarget(
            name: "AlbumCuratorTests",
            dependencies: ["AlbumCuratorApp"],
            path: "Tests/AlbumCuratorTests"
        )
    ]
)
