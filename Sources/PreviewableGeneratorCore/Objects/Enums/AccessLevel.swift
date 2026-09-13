//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// The declared visibility of a type, ordered from least to most visible.
///
/// Ordering supports validation that factory parameter types are at least as visible as the factory.
enum AccessLevel: Int, Comparable {

  /// File-scoped access, combining `private` and `fileprivate` for generator checks.
  case restricted
  /// Access within the current module.
  case `internal`
  /// Access within the current package.
  case `package`
  /// Access from importing modules, also representing `open` declarations.
  case `public`

  /// The keyword a developer would write for this level.
  var keyword: String {
    switch self {
    case .restricted: "private"
    case .internal: "internal"
    case .package: "package"
    case .public: "public"
    }
  }

  /// Reads the level from a declaration's modifiers, defaulting to `internal` as Swift does.
  init(modifiers: DeclModifierListSyntax) {
    for modifier in modifiers {
      switch modifier.name.text {
        // `open` is only more permissive than `public` for subclassing, which never affects visibility here.
      case "open", "public": self = .public; return
      case "package": self = .package; return
      case "private", "fileprivate": self = .restricted; return
      default: continue
      }
    }
    self = .internal
  }

  static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
