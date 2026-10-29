//
// Copyright © 2026 Mercury contributors. MIT licensed.
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
/// The build tool reads only the current module. The `parameters` list supplies external initializer labels and
/// types in call order. The generated factory applies the same default-resolution rules as module-local factories.
///
/// ```swift
/// @PreviewableFake(parameters: [("token", String.self), ("expirationDate", Date.self)])
/// extension AppCheckToken {}
/// ```
///
/// Requires an unconstrained extension of a non-generic type and a nonempty list of distinct parameter labels.
/// Initializer signature mismatches are diagnosed when generated source is compiled.
/// The factory traps outside Debug builds.
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
