// swift-tools-version: 6.4
// 6.4 is the first tools version that knows about iOS 27.

import PackageDescription

let package = Package(
    name: "NavidromeCore",
    platforms: [.iOS(.v27)],
    products: [
        .library(name: "NavidromeCore", targets: ["NavidromeCore"]),
    ],
    targets: [
        .target(name: "NavidromeCore"),
        .testTarget(
            name: "NavidromeCoreTests",
            dependencies: ["NavidromeCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
