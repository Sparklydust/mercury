//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import PreviewableGeneratorCore

/// Identifies the inputs and output of a successful generation without retaining parsed syntax.
struct PreviewableGenerationCache: Codable, Equatable {

  /// The digest of source paths, source contents and the generator executable's build metadata.
  let inputs: String
  /// The digest used to reject missing or externally modified generated output.
  let output: String

  /// Hashes all generation inputs, including the tool identity so rebuilding it invalidates the cache.
  /// - Parameters:
  ///   - files: The source files in generation order.
  ///   - executable: The generator executable path.
  /// - Throws: When the executable's filesystem metadata cannot be read.
  static func fingerprint(files: [PreviewableSourceFile], executable: String) throws -> String {
    let executable = URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
    let attributes = try FileManager.default.attributesOfItem(atPath: executable)
    var digest = SHA256()
    let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let identity = "\(executable):\(attributes[.size] ?? 0):\(modified)"
    digest.update(data: Data(identity.utf8))
    for file in files {
      // Length prefixes distinguish paths and source text even when their contents include delimiters.
      for value in [file.path, file.text] {
        let data = Data(value.utf8)
        digest.update(data: Data("\(data.count):".utf8))
        digest.update(data: data)
      }
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }

  /// Returns a stable content digest for a generated file.
  /// - Parameter text: The generated source text.
  static func fingerprint(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
