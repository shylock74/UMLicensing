// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "UMLicensing",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "UMLicensing",
            targets: ["UMLicensing"]
        ),
    ],
    dependencies: [
        // I pulsanti delle schermate di licenza sono gli UMUICapsuleButton di questo
        // package: le finestre devono somigliare al resto delle app, non ai default di
        // SwiftUI. Il riferimento è al branch perché UMUIControls non ha ancora tag.
        .package(url: "https://github.com/shylock74/UMUIControls.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "UMLicensing",
            dependencies: [
                .product(name: "UMUIControls", package: "UMUIControls")
            ],
            resources: [
                .process("MailTemplate.txt")
            ]
        ),
        .testTarget(
            name: "UMLicensingTests",
            dependencies: ["UMLicensing"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
