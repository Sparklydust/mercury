//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import Foundation
import PackagePlugin

/// A build-tool plugin that generates preview doubles and fake factories from target source files.
@main
struct PreviewableBuildToolPlugin: BuildToolPlugin {

    /// Creates the source-generation command for a Swift package target.
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
