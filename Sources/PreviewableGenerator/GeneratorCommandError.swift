//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// A failure in how the generator was invoked, as opposed to one in the sources it read.
enum GeneratorCommandError: Error, CustomStringConvertible {

  case missingOutputPath

  var description: String {
    switch self {
    case .missingOutputPath: "error: PreviewableGenerator requires an output path"
    }
  }
}
