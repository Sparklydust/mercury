//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// A diagnostic produced when a Previewable macro is attached to an unsupported declaration.
enum PreviewableMacroError: Error, CustomStringConvertible {

    /// A diagnostic with a caller-facing explanation.
    case message(String)

    var description: String {
        switch self {
        case let .message(message): message
        }
    }
}
