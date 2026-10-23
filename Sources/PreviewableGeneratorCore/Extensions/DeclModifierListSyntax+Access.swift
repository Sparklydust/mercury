//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

extension DeclModifierListSyntax {

  /// The access-level keyword to copy onto a generated declaration, with a trailing space, or an empty string.
  ///
  /// `open` is downgraded to `public`: it applies to neither the static factories nor the extension members
  /// generated here.
  var accessPrefix: String {
    let accessLevels = ["open", "public", "package"]

    guard let modifier = first(where: { accessLevels.contains($0.name.text) })
    else { return String() }

    return modifier.name.text == "open" ? "public " : "\(modifier.name.text) "
  }

  /// Whether the modified declaration belongs to the type rather than to an instance.
  var isStatic: Bool {
    contains { ["class", "static"].contains($0.name.text) }
  }

  /// Whether the modified declaration is invisible outside its own file, and so unusable from generated source.
  var isFileScoped: Bool {
    contains { ["private", "fileprivate"].contains($0.name.text) }
  }
}
