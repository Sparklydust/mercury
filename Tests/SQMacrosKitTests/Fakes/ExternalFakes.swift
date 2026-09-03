//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import Foundation
import SQMacrosKit

/// Exercises a type declared outside the module, whose members the generator cannot read.
@PreviewableFake(members: [("identifier", String.self)])
extension Locale {
    // Intentionally empty: `Locale` is a Foundation type.
}

/// Exercises an external member list carrying an optional, which the resolver still defaults.
@PreviewableFake(members: [("name", String.self), ("value", String?.self)])
extension URLQueryItem {
    // Intentionally empty: `URLQueryItem` is a Foundation type.
}
