//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

extension AccessorBlockSyntax {

    /// Whether the accessors declare a setter, which decides if a generated stub needs one too.
    var isSettable: Bool {
        guard case .accessors(let declared) = accessors else { return false }
        return declared.contains { $0.accessorSpecifier.tokenKind == .keyword(.set) }
    }
}
