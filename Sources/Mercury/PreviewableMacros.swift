/// Marks a protocol for Debug-only test-double generation.
///
/// The build tool generates a conforming `Double` with automatic stubs, method and parameter recording, and a shared
/// `preview` instance. It also emits a preview dependency accessor that traps when evaluated outside Debug builds and
/// SwiftUI previews.
///
/// Apply the macro only to protocols without associated types or generic constraints.
@attached(peer, names: suffixed(Double))
public macro PreviewableDouble() = #externalMacro(
  module: "PreviewableMacrosPlugin",
  type: "PreviewableDoubleMacro"
)

/// Marks a structure or class for preview fake-factory generation.
///
/// Debug builds receive a `fake(...)` factory with individually overridable defaults. Other builds receive a trapping
/// signature so SwiftUI previews remain type-checkable without constructing fake values. Classes with generated
/// properties require mutable properties and an accessible parameterless initializer.
@attached(extension, names: named(fake))
public macro PreviewableFake() = #externalMacro(
  module: "PreviewableMacrosPlugin",
  type: "PreviewableFakeMacro"
)
