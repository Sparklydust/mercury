//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// Marks a protocol for Debug-only test-double generation.
///
/// The build tool generates a conforming `Double` with automatic stubs, method and parameter recording, and a shared
/// `preview` instance. It also emits a lower-camel-case double accessor that traps outside Debug builds and
/// SwiftUI previews.
///
/// Apply the macro only to protocols without associated types or generic constraints.
@attached(peer, names: suffixed(Double))
public macro PreviewableDouble() = #externalMacro(
    module: "PreviewableMacrosPlugin",
    type: "PreviewableDoubleMacro"
)

/// Marks a structure or class for fake-factory generation.
///
/// The generated `fake(...)` factory returns an instance with generated defaults or caller-provided overrides in
/// Debug builds, test targets, and SwiftUI previews. Its signature remains available in other builds for preview
/// type checking, but invoking it traps.
/// Classes with generated properties require mutable properties and an accessible parameterless initializer.
///
/// The macro carries a peer role rather than an extension role because it generates nothing itself: it validates the
/// declaration, and the build tool plugin writes the factory. An extension role would also make the macro
/// unattachable to the extensions ``PreviewableFake(members:)`` relies on.
@attached(peer)
public macro PreviewableFake() = #externalMacro(
    module: "PreviewableMacrosPlugin",
    type: "PreviewableFakeMacro"
)

/// Marks an extension of a type declared outside this module for fake-factory generation.
///
/// The build tool only reads the sources of the module it compiles, so it cannot discover the stored properties of a
/// type another framework declares. List them in `members` instead, in the order the type's initializer expects them,
/// and the generated `fake(...)` calls that initializer with the same generated defaults an owned type receives.
///
/// ```swift
/// @PreviewableFake(members: [("token", String.self), ("expirationDate", Date.self)])
/// extension AppCheckToken {}
/// ```
///
/// Apply the macro to an unconstrained extension of a non-generic type, and keep `members` in step with the
/// initializer being called: the build tool cannot check a signature it cannot read, so a mismatch surfaces as a
/// compiler error inside the generated file.
///
/// - Parameter members: The name and type of every value the generated factory passes to the type's initializer.
@attached(peer)
public macro PreviewableFake(members: [(String, Any.Type)]) = #externalMacro(
    module: "PreviewableMacrosPlugin",
    type: "PreviewableFakeMacro"
)
