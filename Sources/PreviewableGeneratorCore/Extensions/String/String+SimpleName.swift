//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

extension String {

    /// The last component of a dot-qualified name, so `Trading.Order` reads as `Order`.
    var simpleName: String {
        split(separator: ".").last.map(String.init) ?? self
    }

    /// Whether the string spells a bare Swift identifier, and so can be used as a generated parameter name.
    var isIdentifier: Bool {
        guard let first = unicodeScalars.first,
              CharacterSet.letters.contains(first) || first == "_"
        else { return false }
        return unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_"
        }
    }
}
