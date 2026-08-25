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
@attached(extension, names: named(fake))
public macro PreviewableFake() = #externalMacro(
  module: "PreviewableMacrosPlugin",
  type: "PreviewableFakeMacro"
)
