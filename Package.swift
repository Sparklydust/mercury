// swift-tools-version: 6.3

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "sqm-ios-macros",
    platforms: [
        .iOS(.v16),
        .macOS(.v26)
    ],
    products: [
        .library(name: "SQMacrosKit", targets: ["SQMacrosKit"]),
        .plugin(name: "PreviewableBuildToolPlugin", targets: ["PreviewableBuildToolPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/lukaskubanek/LoremSwiftum.git", from: "2.2.1"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.0")
    ],
    targets: [
        .macro(
            name: "PreviewableMacrosPlugin",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax")
            ]
        ),
        .target(name: "SQMacrosKit", dependencies: ["PreviewableMacrosPlugin"]),
        .target(
            name: "PreviewableGeneratorCore",
            dependencies: [
                .product(name: "LoremSwiftum", package: "LoremSwiftum"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ]
        ),
        .executableTarget(name: "PreviewableGenerator", dependencies: ["PreviewableGeneratorCore"]),
        .plugin(
            name: "PreviewableBuildToolPlugin",
            capability: .buildTool(),
            dependencies: ["PreviewableGenerator"]
        ),
        .testTarget(
            name: "SQMacrosKitTests",
            dependencies: [
                "SQMacrosKit",
                "PreviewableGeneratorCore",
                "PreviewableMacrosPlugin",
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax")
            ],
            plugins: ["PreviewableBuildToolPlugin"]
        )
    ]
)
