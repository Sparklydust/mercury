//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// Marks a structure or class for fake-factory generation.
///
/// The generated `fake(...)` factory returns an instance with generated defaults or caller-provided overrides in
/// Debug builds, test targets, and SwiftUI previews. Its signature remains available in other builds for preview
/// type checking, but invoking it traps.
/// Classes with generated properties require mutable properties and an accessible parameterless initializer.
///
/// A globally isolated type keeps its isolation. The factory is generated into an extension of that type and calls
/// an initializer that is isolated too, so it is callable from that actor and nowhere else — unlike a double, whose
/// initializer the build tool declares itself and can therefore make `nonisolated`.
///
/// The macro carries a peer role rather than an extension role because it generates nothing itself: it validates the
/// declaration, and the build tool plugin writes the factory. An extension role would also make the macro
/// unattachable to the extensions ``PreviewableFake(parameters:)`` relies on.
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
///
/// - Parameter parameters: The name and type of every value the generated factory passes to the type's initializer.
@attached(peer)
public macro PreviewableFake(parameters: [(String, Any.Type)]) = #externalMacro(
    module: "PreviewableMacrosPlugin",
    type: "PreviewableFakeMacro"
)
