# Mercury

Mercury generates model fakes and protocol doubles for tests and previews.

**Requirements:** Swift 6.4 or later and an Apple Silicon Mac for builds.
Deployment targets: iOS 16, macOS 13, tvOS 26, visionOS 26, and watchOS 26 or later.

## Setup

Add both the library and build plugin to each target that uses the macros:

```swift
.target(
  name: "YourFeature",
  dependencies: [.product(name: "Mercury", package: "mercury")],
  plugins: [.plugin(name: "PreviewableBuildToolPlugin", package: "mercury")]
)
```

Import `Mercury` in annotated source files.

## Dependency doubles

```swift
import Mercury

@PreviewableDouble
protocol ProfileServiceProtocol: Sendable {
  func name(for id: Int) async throws -> String
}
```

```swift
let serviceDouble = ProfileServiceDouble()
serviceDouble.nameStub = "Alex"
let result = try await serviceDouble.name(for: 42)
#expect(result == "Alex")
#expect(serviceDouble.calledMethods == ["name(for:)"])
```

Use `<property>Stub` and `<method>Stub` for responses, `<method>ErrorStub` for a persistent error,
and `<method>ErrorsStub` for queued errors. `calledMethods` and `passedParameters` record invocations;
closure arguments are excluded. Stub access and recording are synchronized. Use a fresh double per test.

Nonisolated doubles require `Sendable` responses and arguments. Protocols and individual requirements retain
their global-actor isolation.

Actor-annotated requirements record arguments in a separate dictionary: `@MainActor` uses `mainActorPassedParameters`,
and `@Scope.Context` uses `scope_ContextPassedParameters`. Read these on the corresponding actor.
`calledMethods` records all calls.

### Generic methods

```swift
@PreviewableDouble
protocol ServerProtocol: Sendable {
  func make<Value: Codable & Sendable>(for type: Value.Type) async throws -> Value
}
```

```swift
let serverDouble = ServerDouble()
serverDouble.makeStub.set("ready", for: String.self)
serverDouble.makeStub.set(42, for: Int.self)
serverDouble.makeStub.set(nil, for: String?.self)
serverDouble.makeStub.remove(for: Int.self)
```

Generic responses are keyed by return type and must be `Sendable`. Constrain generic and associated result types
accordingly. An explicit optional `nil` counts as configured; calling an unconfigured type traps.

## Model fakes

```swift
@PreviewableFake
struct Profile: Sendable {
  let id: Int
  let name: String
}

let profile = Profile.fake()
let namedProfile = Profile.fake(name: "Alex")
```

Parameters have repeatable defaults and accept overrides. Defaults cover common scalar types, optionals,
collections, simple enums, and annotated types. Computed properties and initialized constants are excluded.
Override defaults when application validation requires specific values.

Factories preserve throwing construction; call them with `try` when required.

For an external type, describe its accessible initializer:

```swift
@PreviewableFake(
  parameters: [("value", Int.self)],
  throwing: true
)
extension ExternalToken {}
```

Omit `throwing` for a nonthrowing initializer.

## Previews and Release builds

Use `ProfileServiceDouble.preview` for a shared preview instance. It retains state between accesses.

Double classes, stub and spy storage, and fake construction compile only under `#if DEBUG`.
Keep `DEBUG` out of Release compilation conditions.

Release retains placeholder `fake()` factories and protocol-typed preview accessors so preview code can type-check.
Calling these placeholders traps; fake calls are not rejected at compile time. Keep their use in tests or previews,
or guard call sites with `#if DEBUG`.

The bundled generator and macro executables run on the build machine and are not embedded in the application.

## Supported construction

Unsupported construction produces a diagnostic on the annotated declaration.

- Structs need a usable memberwise or matching accessible initializer. Hidden fields need a matching initializer.
- Classes need mutable fields and an accessible parameterless initializer; subclasses must declare it explicitly.
- Generic fields need constructible defaults; a bare `Value` has none. Required nested defaults cannot form a cycle.
- Nested types need accessible ancestors. Put actor isolation on the type, not its initializer.
- Inherited protocols must be readable in the same target. Associated types, protocol-level constraints, overloads,
  static requirements, subscripts, and generic thrown errors are unsupported.
- Annotations inside conditional blocks, function bodies, or extensions with nested declarations are unsupported.
- A throwing fake cannot supply a nonthrowing double's stored default.

## Development

Run `swift test` locally. CI also verifies bundled tools and generated consumers, runs tests with Thread Sanitizer,
and builds Release.

### Updating bundled tools

Mercury bundles the generator and macro plugin to avoid compiling them and SwiftSyntax in consumer builds.
Consumers do not need to rebuild these binaries.

Rebuild after changing generator, generator core, macro implementation or launcher sources, `Package.swift`,
`Package.resolved`, or `Scripts/generator-artifact.py`. README and test-only edits do not require rebuilding.

From the repository root, using an Apple Silicon Mac with Xcode 27 / Swift 6.4 and Python 3:

```sh
python3 Scripts/generator-artifact.py build --version 1.0.0
```

Use the intended release version. The command builds both tools for Apple Silicon, packages and signs them,
updates checksums and the macro revision, and verifies the result. Include the following with the source changes:

- `Artifacts/PreviewableGenerator.artifactbundle/` (executables, metadata, and SwiftSyntax license).
- `Sources/PreviewableMacrosLauncher/BundledMacroRevision.swift`.

To verify the bundle without rebuilding:

```sh
python3 Scripts/generator-artifact.py verify
```

Verification checks source fingerprints, checksums, architectures, and signatures. CI rejects a stale bundle.
For source development, run `MERCURY_BUILD_GENERATOR_FROM_SOURCE=1 swift test` before rebuilding the bundle.
