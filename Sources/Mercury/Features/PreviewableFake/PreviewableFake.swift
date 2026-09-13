//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// Marks a structure or class for fake-factory generation.
///
/// The generated `fake(...)` factory returns an instance with generated defaults or caller-provided overrides in
/// Debug builds, Debug test targets, and SwiftUI previews. Its signature remains available in other builds for preview
/// type checking, but invoking it traps.
/// Classes with generated properties require mutable properties and an accessible parameterless initializer.
///
/// The factory preserves actor isolation and throws when initialization or a nested default can throw.
/// Every generated parameter has an automatic default; unsupported construction produces a source diagnostic.
@attached(peer)
public macro PreviewableFake() = #externalMacro(
    module: "PreviewableMacrosPlugin",
    type: "PreviewableFakeMacro"
  )

/// Marks an extension of a type declared outside this module for fake-factory generation.
///
/// The build tool only reads the sources of the module it compiles, so it cannot discover the stored properties of a
/// type another framework declares. List them in `parameters` instead, in the order the type's initializer expects them,
/// and the generated `fake(...)` calls that initializer with the same generated defaults an owned type receives.
///
/// ```swift
/// @PreviewableFake(parameters: [("token", String.self), ("expirationDate", Date.self)])
/// extension AppCheckToken {}
/// ```
///
/// Apply the macro to an unconstrained extension of a non-generic type, and keep `parameters` in step with the
/// initializer being called: the build tool cannot check a signature it cannot read, so a mismatch surfaces as a
/// compiler error inside the generated file.
/// - Parameters:
///   - parameters: The labels and types accepted by the external initializer.
///   - throwing: Whether the external initializer throws.
@attached(peer)
public macro PreviewableFake(
  parameters: [(String, Any.Type)],
  throwing: Bool = false
) = #externalMacro(
    module: "PreviewableMacrosPlugin",
    type: "PreviewableFakeMacro"
  )
