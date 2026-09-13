//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import PackagePlugin

/// A build-tool plugin that generates preview doubles and fake factories from target source files.
@main
struct PreviewableBuildToolPlugin: BuildToolPlugin {

  /// Creates a source-generation command, or no commands for a target without Swift module sources.
  /// - Parameters:
  ///   - context: The package plugin context used to locate the generator and output directory.
  ///   - target: The target whose Swift source files become generator inputs.
  /// - Throws: When the generator tool cannot be located.
  func createBuildCommands(
    context: PluginContext,
    target: Target
  ) throws -> [Command] {
    guard let target = target as? SourceModuleTarget else { return [] }
    return try commands(
      tool: context.tool(named: "PreviewableGenerator").url,
      sourceFiles: target.sourceFiles(withSuffix: "swift").map(\.url),
      workDirectory: context.pluginWorkDirectoryURL
    )
  }

  /// Declares generation of one derived file with source inputs tracked by the build system.
  /// - Parameters:
  ///   - tool: The generator executable URL.
  ///   - sourceFiles: The Swift inputs passed after the output path.
  ///   - workDirectory: The plugin directory containing the derived output.
  /// - Throws: No errors in the current implementation.
  private func commands(
    tool: URL,
    sourceFiles: [URL],
    workDirectory: URL
  ) throws -> [Command] {
    let output = workDirectory.appending(path: "Previewables.generated.swift")
    return [
      .buildCommand(
        displayName: "Generate Debug previewables",
        executable: tool,
        arguments: [output.path] + sourceFiles.map(\.path),
        inputFiles: sourceFiles,
        outputFiles: [output]
      )
    ]
  }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension PreviewableBuildToolPlugin: XcodeBuildToolPlugin {

  /// Creates the source-generation command for an Xcode target.
  /// - Parameters:
  ///   - context: The Xcode plugin context used to locate the generator and output directory.
  ///   - target: The target whose Swift source inputs are processed.
  /// - Throws: When the generator tool cannot be located.
  func createBuildCommands(
    context: XcodePluginContext,
    target: XcodeTarget
  ) throws -> [Command] {
    let sourceFiles = target.inputFiles
      .filter { $0.type == .source && $0.url.pathExtension == "swift" }
      .map(\.url)
    return try commands(
      tool: context.tool(named: "PreviewableGenerator").url,
      sourceFiles: sourceFiles,
      workDirectory: context.pluginWorkDirectoryURL
    )
  }
}
#endif
