# Changelog

## 1.0.0

Initial public release.

### Added

- `@PreviewableDouble` generates configurable protocol doubles with response stubs, persistent and queued errors, call recording, and captured arguments.
- Doubles support overloads, inherited requirements, associated types, generic responses, properties, subscripts, scoped static stubs, and actor isolation.
- Async methods and getters support observation, bounded waits for call handles, per-call pauses and resumes, cancellation, and captured responses and errors.
- `@PreviewableFake` generates model factories with default values and selected overrides, including factories for types initialized through extensions.
- `PreviewableSynthesizable` supplies defaults for supported scalar and Foundation types and allows custom defaults for external types.
- The Swift Package Manager build plugin generates source with source-located diagnostics, dependency validation, and generation caching.
- Bundled generator and macro executables support Apple Silicon consumer builds; Linux builds the tools from source.
- MIT licensing, public API documentation, and guides covering installation, tests, SwiftUI previews, development, concurrency, supported declarations, and limitations.
- Semantic versioning for the public macros, runtime APIs, and generated consumer APIs. Generated-code SPI is excluded from the compatibility contract.

### Requirements

- Swift 6.4 or later; Xcode 27 or later on macOS.
- An Apple Silicon Mac, or Linux with source-built tools.
- Apple deployment targets of iOS 18, macOS 15, tvOS 18, visionOS 2, and watchOS 11 or later.

### Build behavior

- Working doubles and fake factories are available in Debug builds. Guard development-only call sites with `#if DEBUG`.
- Release builds retain placeholder fake factories and protocol-typed preview accessors for type checking; calling them traps. Generated double classes are unavailable in Release.
- Build tools run during compilation and are not embedded in consumer applications.
