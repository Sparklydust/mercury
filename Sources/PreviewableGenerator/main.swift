import Foundation
import PreviewableGeneratorCore

/// The command-line entry point that writes generated Previewable source for a build target.
@main
enum PreviewableGenerator {

  /// Reads the requested Swift sources and writes their generated Previewable declarations.
  /// - Throws: When the output path is missing, a source cannot be read, generation fails, or output cannot be written.
  static func main() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let outputPath = arguments.first else { throw GeneratorCommandError.missingOutputPath }

    let sources = try arguments.dropFirst().map {
      try String(contentsOfFile: $0, encoding: .utf8)
    }
    let generated = try PreviewableSourceGenerator.generate(from: sources)
    try generated.write(toFile: outputPath, atomically: true, encoding: .utf8)
  }
}

private enum GeneratorCommandError: Error {
  case missingOutputPath
}
