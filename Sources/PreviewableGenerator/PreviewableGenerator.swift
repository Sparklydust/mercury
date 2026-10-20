//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import PreviewableGeneratorCore

/// The command-line entry point that writes generated Previewable source for a build target.
enum PreviewableGenerator {

  /// Reads the requested Swift sources and writes their generated Previewable declarations.
  /// The first argument is the output path, followed by input paths or `--input-file-list` and a JSON path array.
  /// - Throws: For a missing output path, invalid source declarations, or file read and write failures.
  static func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let outputPath = arguments.first else { throw GeneratorCommandError.missingOutputPath }

    let paths = try inputPaths(from: Array(arguments.dropFirst()))
    let files = try sourceFiles(at: paths)
    let cacheURL = URL(fileURLWithPath: outputPath + ".cache.json")
    let executable = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
    let inputDigest = try PreviewableGenerationCache.fingerprint(files: files, executable: executable)
    let previous = try? String(contentsOfFile: outputPath, encoding: .utf8)
    guard !isCached(previous, at: cacheURL, inputDigest: inputDigest) else { return }
    let generated = try PreviewableSourceGenerator.generate(from: files)
    try write(generated, to: outputPath, previous: previous, cacheURL: cacheURL, inputDigest: inputDigest)
  }
}

private extension PreviewableGenerator {

  static func inputPaths(from inputs: [String]) throws -> [String] {
    guard inputs.first == "--input-file-list" else { return inputs }
    guard inputs.count == 2 else { throw GeneratorCommandError.missingInputFileList }
    return try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: inputs[1])))
  }

  static func sourceFiles(at paths: [String]) throws -> [PreviewableSourceFile] {
    try paths.sorted().map {
      PreviewableSourceFile(path: $0, text: try String(contentsOfFile: $0, encoding: .utf8))
    }
  }

  static func isCached(
    _ previous: String?,
    at cacheURL: URL,
    inputDigest: String
  ) -> Bool {
    guard let previous, let data = try? Data(contentsOf: cacheURL),
          let cache = try? JSONDecoder().decode(PreviewableGenerationCache.self, from: data),
          cache.inputs == inputDigest, cache.output == PreviewableGenerationCache.fingerprint(previous)
    else { return false }

    return true
  }

  static func write(
    _ generated: String,
    to outputPath: String,
    previous: String?,
    cacheURL: URL,
    inputDigest: String
  ) throws {
    // Preserve the modification time so an unchanged declaration does not invalidate consumer compilation.
    if previous != generated {
      try generated.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }
    let cache = PreviewableGenerationCache(
      inputs: inputDigest,
      output: PreviewableGenerationCache.fingerprint(generated)
    )
    try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
  }
}
