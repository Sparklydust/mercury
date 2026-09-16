# Mercury

Mercury generates model fakes and protocol doubles for tests and previews.

**Requirements:** Swift 6.4 or later and an Apple Silicon Mac for builds. Deployment targets: iOS 16, macOS 13, tvOS 26, visionOS 26, and watchOS 26 or later.

## Setup

### Xcode project

1. Choose **File → Add Package Dependencies…** and enter `https://github.com/Sparklydust/mercury`.
2. Add the **Mercury** library product to the app or framework target containing the annotated source files.
3. Select that target, open **Build Phases → Run Build Tool Plug-ins**, click **+**, and add **PreviewableBuildToolPlugin**.
4. Add `import Mercury` to annotated source files and build the target. Approve Mercury's plug-in and macros if Xcode prompts.

Repeat the library and plug-in setup for each target that declares annotations, including test targets. Xcode generates and compiles `Previewables.generated.swift` automatically.

### Swift package

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

Use `<property>Stub` and `<method>Stub` for responses, `<method>ErrorStub` for a persistent error, and `<method>ErrorsStub` for queued errors. `calledMethods` and `passedParameters` record invocations; closure arguments are excluded. Stub access and recording are synchronized. Use a fresh double per test.

Doubles preserve the protocol's sendability, including inherited `Sendable` conformance. Legacy protocols need no additional conformance: their instance doubles accept non-Sendable arguments, responses, closures, and associated types. Sendable doubles require Sendable values outside actor isolation. Protocols and individual requirements retain their global-actor isolation.

Actor-annotated requirements record arguments in a separate dictionary: `@MainActor` uses `mainActorPassedParameters`, and `@Scope.Context` uses `scope_ContextPassedParameters`. Read these on the corresponding actor. `calledMethods` records all calls.

### Generic methods

```swift
@PreviewableDouble
protocol ServerProtocol: Sendable {
  func make<Value: Codable & Sendable>(for type: Value.Type) async throws -> Value
}
```

Configure the response, then call the original protocol method:

```swift
let serverDouble = ServerDouble()
serverDouble.makeStub.set("ready", for: String.self)
let result = try await serverDouble.make(for: String.self)
#expect(result == "ready")
```

`make(for:)` keeps the original signature. `makeStub` configures a response for each concrete return type. Sendable doubles use `PreviewableResponses`; legacy instance doubles and actor-isolated requirements use `PreviewableLocalResponses`, which accepts non-Sendable values. Calling an unconfigured type traps. An explicit optional `nil` counts as configured.

### Overloads, associated types, and subscripts

```swift
@PreviewableDouble
protocol StoreProtocol<Value>: Sendable {
  associatedtype Value: Sendable
  func load(id: Int) -> Value
  func load(id: String) -> Value
  subscript(_ index: Int) -> Value { get set }
  static var revision: Int { get set }
}

let storeDouble = StoreDouble<String>()
storeDouble.loadIdIntStub = "number"
storeDouble.loadIdStringStub = "text"
let result = storeDouble.load(id: 42)

storeDouble.subscriptStub = "ready"
let value = storeDouble[1]
```

Overloads retain their original signatures and get independent stubs and recording keys. Names include argument labels and types; return types and a stable signature suffix resolve collisions. Existing single-method names remain. Equivalent standard types and known local aliases share one signature; imported aliases retain their written identity.

Associated types become generic parameters, ordered by primary associated types then remaining names alphabetically. Concrete same-type bindings become aliases. Responses without defaults must be configured before use; otherwise they trap. Generic doubles provide fresh `.preview` instances and no global preview accessor.

Subscript getters use one response for all indices. Setters record indices and the assigned value without changing that response. Getter and setter recordings use separate keys. Indices do not require `Hashable`.

### Static requirements

```swift
StoreDouble<String>.withStaticStubs {
  StoreDouble<String>.revision = 42
  // Invoke the consumer that uses StoreDouble<String>'s static requirements here.
}
```

Use `await` for asynchronous work. Each scope has fresh synchronized reference state, isolated by concrete double type. Child tasks inherit that state; nested scopes restore it on exit. Detached tasks need their own scope. Access outside a scope traps. Static recordings are available on the double type inside the scope.

Static state is shared across inheriting tasks, so its values must remain Sendable or protected by a global actor, including for legacy protocols.

Concurrent configuration is memory-safe but ordering is unspecified. Configure before spawning child tasks for deterministic responses. Error queues are atomic and FIFO; assignment to concurrent callers depends on scheduling.

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

Parameters have repeatable defaults and accept overrides. Defaults cover common scalar types, optionals, collections, simple enums, and annotated types. Computed properties and initialized constants are excluded. Override defaults when application validation requires specific values.

Local nongeneric aliases use their underlying defaults, including closure storage and throwing construction.

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

Non-Sendable and generic doubles return a fresh instance from `.preview`. The global accessor also returns a fresh instance for non-Sendable doubles. These accessors are nonisolated and require no additional annotations. Keep the returned instance when configuring stubs before injection.

Double classes, stub and spy storage, and fake construction compile only under `#if DEBUG`. Keep `DEBUG` out of Release compilation conditions.

Release retains placeholder `fake()` factories and protocol-typed preview accessors so preview code can type-check. Calling these placeholders traps; fake calls are not rejected at compile time. Keep their use in tests or previews, or guard call sites with `#if DEBUG`.

The bundled generator and macro executables run on the build machine and are not embedded in the application.

## Current limitations

Unsupported construction produces a diagnostic on the annotated declaration.

- Structs need a usable memberwise or matching accessible initializer. Hidden fields need a matching initializer.
- Classes need mutable fields and an accessible parameterless initializer; subclasses must declare it explicitly.
- Generic fields need constructible defaults; a bare `Value` has none. Required nested defaults cannot form a cycle.
- Nested types need accessible ancestors. Put actor isolation on the type, not its initializer.
- Inherited protocols must be readable in the same target. Bare `Self` value types, variadic parameters, and generic thrown errors remain unsupported. Subscripts do not yet support responses keyed by arguments.
- Annotations inside conditional blocks, function bodies, or extensions with nested declarations are unsupported. Protocol requirements inside `#if` blocks are also rejected, including inherited requirements.
- Generated double types and global preview accessors must have unique file-scope names. Conditional file-scope declarations reserve their names across configurations.
- A throwing fake cannot supply a nonthrowing double's stored default.

### Validation scope

- Performance has been measured in one iOS application with eight annotations. Scaling to larger targets and multiple modules remains unverified. A generation cache miss reparses all Swift sources in the target.
- Validation does not yet cover every declared platform at its minimum OS version.

## Development

Run `swift test` locally. CI also verifies bundled tools and generated consumers, runs tests with Thread Sanitizer, and builds Release.

### Updating bundled tools

Mercury bundles the generator and macro plugin to avoid compiling them and SwiftSyntax in consumer builds. Consumers do not need to rebuild these binaries.

Rebuild after changing generator, generator core, macro implementation or launcher sources, `Package.swift`, `Package.resolved`, or `Scripts/generator-artifact.py`. README and test-only edits do not require rebuilding. Source fingerprints include comments and file headers. Finish source edits and formatting before rebuilding.

From the repository root, using an Apple Silicon Mac with Xcode 27 / Swift 6.4 and Python 3:

```sh
python3 Scripts/generator-artifact.py build --version 1.0.0
```

Use the intended release version. The command builds both tools for Apple Silicon, packages and signs them, updates checksums and the macro revision, and verifies the result. Include the following with the source changes:

- `Artifacts/PreviewableGenerator.artifactbundle/` (executables, metadata, and SwiftSyntax license).
- `Sources/PreviewableMacrosLauncher/BundledMacroRevision.swift`.

Verify the final files before committing:

```sh
python3 Scripts/generator-artifact.py verify
```

Verification checks source fingerprints, checksums, architectures, and signatures. CI rejects a stale bundle. For source development, run `MERCURY_BUILD_GENERATOR_FROM_SOURCE=1 swift test` before rebuilding the bundle.
