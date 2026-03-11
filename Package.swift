// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "vapor-sse",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(name: "SSE", targets: ["SSE"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.3"),
    ],
    targets: [
        .target(
            name: "SSE",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
        .testTarget(
            name: "SSETests",
            dependencies: [
                "SSE",
                .product(name: "VaporTesting", package: "vapor"),
            ]
        ),
    ]
)
