//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// A failure in how the generator was invoked, as opposed to one in the sources it read.
enum GeneratorCommandError: Error, CustomStringConvertible {

  /// The command was invoked without the destination file argument.
  case missingOutputPath
  /// The file-list option was invoked without exactly one JSON path.
  case missingInputFileList

  var description: String {
    switch self {
    case .missingOutputPath: "error: PreviewableGenerator requires an output path"
    case .missingInputFileList: "error: --input-file-list requires one JSON file path"
    }
  }
}
