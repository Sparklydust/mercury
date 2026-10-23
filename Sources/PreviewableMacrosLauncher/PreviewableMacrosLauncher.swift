//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Darwin
import Foundation

/// Starts the bundled compiler plugin without compiling its SwiftSyntax dependencies in consumers.
@main
enum PreviewableMacrosLauncher {

  /// Replaces this process while preserving Swift's compiler-plugin communication channels and sandbox.
  static func main() {
    let package = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let bundle = package.appending(path: "Artifacts/PreviewableGenerator.artifactbundle")
    let executable = bundle.appending(path: "bin/PreviewableMacrosPlugin")
    executable.path.withCString { path in
      var arguments = [UnsafeMutablePointer(mutating: path), nil]
      execv(path, &arguments)
    }
    perror("Mercury macro \(bundledMacroRevision) could not start")
    exit(EXIT_FAILURE)
  }
}
