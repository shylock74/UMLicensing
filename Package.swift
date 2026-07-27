// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "UMLicensing",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "UMLicensing",
            targets: ["UMLicensing"]
        ),
    ],
    targets: [
        .target(
            name: "UMLicensing"
        ),
        .testTarget(
            name: "UMLicensingTests",
            dependencies: ["UMLicensing"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
