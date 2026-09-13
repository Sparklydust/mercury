//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// Extracts quoted string parameter defaults from generated source in emission order.
/// - Parameter source: The generated Swift text containing factory parameter declarations.
func generatedStringDefaults(in source: String) -> [String] {
  source.components(separatedBy: "\n").compactMap { line in
    guard line.contains(": String = \"") else { return nil }
    let components = line.split(separator: "\"")
    guard components.count > 1 else { return nil }
    return String(components[1])
  }
}
