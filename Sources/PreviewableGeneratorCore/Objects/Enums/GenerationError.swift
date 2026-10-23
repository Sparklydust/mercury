//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

/// A failure raised while generating, later attributed to a source location.
enum GenerationError: Error, CustomStringConvertible {

  /// A generation failure with the explanation to attach to a source declaration.
  case message(String)

  var description: String {
    switch self {
    case .message(let message): message
    }
  }

  var message: String { description }
}
