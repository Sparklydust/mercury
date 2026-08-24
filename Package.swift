// swift-tools-version: 6.3

import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "Mercury",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
    .visionOS(.v1)
  ],
  products: [
    .library(
      name: "Mercury",
      targets: ["Mercury"]
    ),
    .plugin(
      name: "PreviewableBuildToolPlugin",
      targets: ["PreviewableBuildToolPlugin"]
    )
  ],
  dependencies: [
    .package(
      url: "https://github.com/lukaskubanek/LoremSwiftum.git",
      from: "2.2.1"
    ),
    .package(
      url: "https://github.com/swiftlang/swift-syntax.git",
      exact: "604.0.0-prerelease-2026-06-05"
    )
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
    .target(
      name: "Mercury",
      dependencies: ["PreviewableMacrosPlugin"]
    ),
    .target(
      name: "PreviewableGeneratorCore",
      dependencies: [
        .product(name: "LoremSwiftum", package: "LoremSwiftum"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax")
      ]
    ),
    .executableTarget(
      name: "PreviewableGenerator",
      dependencies: ["PreviewableGeneratorCore"]
    ),
    .plugin(
      name: "PreviewableBuildToolPlugin",
      capability: .buildTool(),
      dependencies: ["PreviewableGenerator"]
    ),
    .testTarget(
      name: "PreviewableMacrosTests",
      dependencies: [
        "PreviewableGeneratorCore",
        "PreviewableMacrosPlugin",
        .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax")
      ]
    )
  ],
  swiftLanguageModes: [.v6]
)
