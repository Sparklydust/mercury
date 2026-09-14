// swift-tools-version: 6.4

import CompilerPluginSupport
import Foundation
import PackageDescription

let buildGeneratorFromSource = ProcessInfo.processInfo.environment["MERCURY_BUILD_GENERATOR_FROM_SOURCE"] == "1"
let buildToolArtifacts = ProcessInfo.processInfo.environment["MERCURY_BUILD_TOOL_ARTIFACTS"] == "1"
let macroSourceDependencies: [Target.Dependency] = [
  .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
  .product(name: "SwiftSyntax", package: "swift-syntax"),
  .product(name: "SwiftSyntaxMacros", package: "swift-syntax")
]

let package = Package(
  name: "mercury",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
    .tvOS(.v26),
    .visionOS(.v26),
    .watchOS(.v26)
  ],
  products: [
    .library(name: "Mercury", targets: ["Mercury"]),
    .plugin(name: "PreviewableBuildToolPlugin", targets: ["PreviewableBuildToolPlugin"])
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.0")
  ],
  targets: [
    // Executable targets allow cross-compiling both host architectures when packaging the macro.
    buildToolArtifacts ? .executableTarget(
      name: "PreviewableMacrosPlugin",
      dependencies: macroSourceDependencies,
      path: "Sources/PreviewableMacrosPlugin"
    ) : .macro(
      name: "PreviewableMacrosPlugin",
      dependencies: buildGeneratorFromSource ? macroSourceDependencies : [],
      path: buildGeneratorFromSource ? "Sources/PreviewableMacrosPlugin" : "Sources/PreviewableMacrosLauncher"
    ),
    .target(name: "Mercury", dependencies: ["PreviewableMacrosPlugin"]),
    .target(
      name: "PreviewableGeneratorCore",
      dependencies: [
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax")
      ]
    ),
    .executableTarget(name: "PreviewableGenerator", dependencies: ["PreviewableGeneratorCore"]),
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
  ] + (buildGeneratorFromSource ? [] : [
    .macro(
      name: "PreviewableMacrosTestsSupport",
      dependencies: macroSourceDependencies,
      path: "Sources/PreviewableMacrosPlugin"
    ),
    .binaryTarget(
      name: "PreviewableGeneratorBinary",
      path: "Artifacts/PreviewableGenerator.artifactbundle"
    )
  ])
)
