// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "vapor-sse",
    platforms: [
        .macOS("26.2"),
        .iOS("26.2"),
    ],
    products: [
        .library(name: "SSE", targets: ["SSE"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "5.0.0-beta.4"),
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
