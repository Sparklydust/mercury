//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// A validation failure paired with the declaration the developer has to change.
struct GenerationFailure {

    let annotation: AnnotatedDeclaration
    let message: String
}
