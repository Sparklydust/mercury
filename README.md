# Mercury

Mercury generates model fakes and protocol doubles for tests and previews.

**Requirements:** Swift 6.3 or later, iOS 26 or macOS 26.

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

Use `<property>Stub` and `<method>Stub` for responses, `<method>ErrorStub` for a persistent error, and `<method>ErrorsStub` for queued errors. `calledMethods` and `passedParameters` record invocations; closure arguments are excluded. Stub access and recording are synchronized. Use a fresh double per test.

Nonisolated doubles require `Sendable` responses and arguments. Globally isolated protocols retain their isolation.

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

Generic responses are keyed by return type. An explicit optional `nil` counts as configured; calling an unconfigured type traps.

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

Generated parameters have defaults and accept overrides. Defaults cover common scalar types, optionals, collections, simple enums, and annotated types. Computed properties and initialized constants are excluded.

### Throwing construction

If construction can throw, the generated `fake()` factory throws:

```swift
enum ValidationError: Error { case invalidCount }

@PreviewableFake
struct CheckedValue {
  let count: Int

  init(count: Int) throws {
    guard count > 0 else { throw ValidationError.invalidCount }
    self.count = count
  }
}

let value = try CheckedValue.fake()
```

For an external type, specify the accessible initializer:

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

Fakes and doubles are available in Debug. Release builds retain their API signatures for compilation; calling them traps.

## Supported construction

Unsupported construction produces a diagnostic on the annotated declaration.

- Structs need a usable memberwise or matching accessible initializer. Classes need mutable generated fields and an accessible parameterless initializer. Hidden fields need a matching initializer.
- Generic fields need constructible defaults; a bare `Value` has none. Required nested defaults cannot form a cycle.
- Nested types need accessible ancestors. Put actor isolation on the type, not its initializer.
- Inherited protocols must be readable in the same target. Associated types, protocol-level constraints, overloads, static requirements, subscripts, and generic thrown errors are unsupported.
- Annotations inside conditional blocks, function bodies, or extensions with nested declarations are unsupported.
- A throwing fake cannot supply a nonthrowing double's stored default.

Override defaults when application validation requires specific values.

## Development

Run `swift test` locally. CI also checks generated consumers, runs the full suite with Thread Sanitizer, and builds Release.
