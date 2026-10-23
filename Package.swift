// swift-tools-version: 6.4

import CompilerPluginSupport
import Foundation
import PackageDescription

#if os(Linux)
// Bundled tools target macOS; Linux builds the same generator and macros from source.
let buildGeneratorFromSource = true
#else
let buildGeneratorFromSource = ProcessInfo.processInfo.environment["MERCURY_BUILD_GENERATOR_FROM_SOURCE"] == "1"
#endif
let buildToolArtifacts = ProcessInfo.processInfo.environment["MERCURY_BUILD_TOOL_ARTIFACTS"] == "1"
let macroSourceDependencies: [Target.Dependency] = [
  .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
  .product(name: "SwiftSyntax", package: "swift-syntax"),
  .product(name: "SwiftSyntaxMacros", package: "swift-syntax")
]

let package = Package(
  name: "mercury",
  platforms: [
    .iOS(.v27),
    .macOS(.v27),
    .tvOS(.v27),
    .visionOS(.v27),
    .watchOS(.v27)
  ],
  products: [
    .library(name: "Mercury", targets: ["Mercury"]),
    .plugin(name: "PreviewableBuildToolPlugin", targets: ["PreviewableBuildToolPlugin"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.0")
  ],
  targets: [
    // An executable target exposes the macro implementation as a product for packaging.
    buildToolArtifacts
    ? .executableTarget(
      name: "PreviewableMacrosPlugin",
      dependencies: macroSourceDependencies,
      path: "Sources/PreviewableMacrosPlugin"
    )
    : .macro(
      name: "PreviewableMacrosPlugin",
      dependencies: buildGeneratorFromSource ? macroSourceDependencies : [],
      path: buildGeneratorFromSource ? "Sources/PreviewableMacrosPlugin" : "Sources/PreviewableMacrosLauncher"
    ),
    .target(name: "Mercury", dependencies: ["PreviewableMacrosPlugin"]),
    .target(
      name: "PreviewableGeneratorCore",
      dependencies: [
        .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax")
      ]
    ),
    .executableTarget(
      name: "PreviewableGenerator",
      dependencies: [
        "PreviewableGeneratorCore",
        .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
      ]
    ),
    .plugin(
      name: "PreviewableBuildToolPlugin",
      capability: .buildTool(),
      dependencies: [buildGeneratorFromSource ? "PreviewableGenerator" : "PreviewableGeneratorBinary"]
    ),
    .testTarget(
      name: "MercuryTests",
      dependencies: [
        "Mercury",
        "PreviewableGeneratorCore",
        .byName(name: buildGeneratorFromSource ? "PreviewableMacrosPlugin" : "PreviewableMacrosTestsSupport"),
        .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax")
      ],
      plugins: ["PreviewableBuildToolPlugin"]
    )
  ] + (
    buildGeneratorFromSource
    ? []
    : [
      .macro(
        name: "PreviewableMacrosTestsSupport",
        dependencies: macroSourceDependencies,
        path: "Sources/PreviewableMacrosPlugin"
      ),
      .binaryTarget(
        name: "PreviewableGeneratorBinary",
        path: "Artifacts/PreviewableGenerator.artifactbundle"
      )
    ]
  )
)
