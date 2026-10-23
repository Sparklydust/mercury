//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

extension AccessorBlockSyntax {

  /// Whether the accessors declare a setter, which decides if a generated stub needs one too.
  var isSettable: Bool {
    guard case .accessors(let declared) = accessors else { return false }
    return declared.contains { $0.accessorSpecifier.tokenKind == .keyword(.set) }
  }
}
