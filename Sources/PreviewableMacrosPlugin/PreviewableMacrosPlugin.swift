//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// The compiler plugin that registers the Previewable macro implementations.
@main
struct PreviewableMacrosPlugin: CompilerPlugin {

  /// The macro implementations exposed by the plugin.
  let providingMacros: [Macro.Type] = [
    PreviewableDoubleMacro.self,
    PreviewableFakeMacro.self
  ]
}
