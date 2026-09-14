# Mercury

Mercury is a Swift package for reusable macros across personal and production projects. Its Previewable feature generates model fakes and dependency doubles for unit tests, SwiftUI previews, and development in Debug mode.

**Requirements:** Swift 6.3 or later, iOS 26 or macOS 26.

## Setup

Add the Mercury package to your project. Attach the `Mercury` library and `PreviewableBuildToolPlugin` to each target containing annotated declarations.

For a Swift package target:

```swift
.target(
  name: "YourFeature",
  dependencies: [.product(name: "Mercury", package: "mercury")],
  plugins: [.plugin(name: "PreviewableBuildToolPlugin", package: "mercury")]
)
```

Import `Mercury` where you use its macros. The plugin reads that target's sources and writes `Previewables.generated.swift` into the build directory.

## Dependency doubles

```swift
import Mercury

@PreviewableDouble
protocol ProfileServiceProtocol: Sendable {
  func name(for id: Int) async throws -> String
}
```

In a Debug test, configure a fresh double and inspect its calls:

```swift
let serviceDouble = ProfileServiceDouble()
serviceDouble.nameStub = "Alex"

let result = try await serviceDouble.name(for: 42)
#expect(result == "Alex")
#expect(serviceDouble.calledMethods == ["name(for:)"])
#expect(serviceDouble.passedParameters["name(for:)"]?.first?.first as? Int == 42)
```

Generated members retain their existing names:

| Member | Purpose |
| --- | --- |
| `<property>Stub` | Configure a property requirement's value. |
| `<method>Stub` | Configure a method's return value. |
| `<method>ErrorStub` | Throw the same error on each invocation. |
| `<method>ErrorsStub` | Consume queued errors before using the persistent error or return value. |
| `calledMethods: [String]` | Record method names in invocation order. |
| `passedParameters: [String: [[Any?]]]` | Record a separate argument array for every invocation. |
| `preview` | Access the shared instance intended for previews. |

A lock protects stubs, invocation records, and error-queue consumption. Mutations such as `errorsStub.append(error)` are synchronized. Separate statements remain separate operations; configure related stubs before starting concurrent work. Closure arguments are not recorded.

Nonisolated doubles require stored responses and recorded arguments to conform to `Sendable`. Protocols isolated to a global actor preserve that isolation. Use a fresh `ProfileServiceDouble()` for each test; nested protocol defaults also receive fresh doubles.

### Generic methods

```swift
@PreviewableDouble
protocol ServerProtocol: Sendable {
  func make<Value: Codable & Sendable>(for type: Value.Type) async throws -> Value
}
```

Configure each concrete return type independently:

```swift
let serverDouble = ServerDouble()
serverDouble.makeStub.set("ready", for: String.self)
serverDouble.makeStub.set(42, for: Int.self)
serverDouble.makeStub.set(nil, for: String?.self)

let value = try await serverDouble.make(for: Int.self)
serverDouble.makeStub.remove(for: Int.self)
```

Each generic method owns a `PreviewableResponses` store. Responses must be `Sendable`. An optional `nil` is a configured response; removing it makes that type unconfigured. Calling an unconfigured return type stops immediately with the method and type in the diagnostic.

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

Every generated field parameter has a default and can be overridden. Stored properties with observers are included; computed properties and constants with existing initial values are excluded.

| Type | Fake default |
| --- | --- |
| Strings | Distinct LoremSwiftum text, randomized when source generation runs. |
| Numbers | Positive values in source order, wrapping within the type's range. |
| Boolean | `false` |
| Optional | `nil` |
| Collections | Empty |
| Enum | First case without an associated value |
| `UUID`, `URL` | Distinct generated values |
| `Date` | January 1, 2024, then one-day increments |
| Annotated model | Its `fake()` factory |
| Annotated protocol | A fresh double |

Doubles use neutral defaults for standard values, such as zero numbers and empty strings.

### Throwing construction

A fake factory throws when its initializer or a required nested fake can throw:

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

Generated factories propagate initialization errors. Overrides retain the same call style, including values whose default requires throwing construction. A throwing closure field defers its error until the closure is invoked.

For a type from another module, describe its accessible initializer explicitly:

```swift
@PreviewableFake(
  parameters: [("value", Int.self)],
  throwing: true
)
extension ExternalToken {}
```

Omit `throwing` for a nonthrowing initializer. Mercury cannot inspect external declarations, so the compiler validates this initializer description.

## Previews and Release builds

For preview dependency injection, use the generated accessor:

```swift
var profileService: Factory<any ProfileServiceProtocol> {
  self { ProfileService() }
    .onPreview { profileServiceDouble }
}
```

The accessor resolves to `ProfileServiceDouble.preview` in Debug. This shared instance is intended for previews; it retains configured state between accesses.

Double implementations and fake data are emitted under `#if DEBUG`. Release builds retain fake-factory signatures and protocol-typed preview accessors so preview injection code can type-check. Calling them in Release traps. Run tests that use generated doubles or fakes in Debug.

## Supported construction

Mercury reports unsupported defaults against the annotated declaration. It does not silently invent an external factory or make an unconstructible field a required argument.

- Structs need a usable memberwise initializer or an accessible initializer matching their generated fields.
- Classes need mutable generated fields and an accessible parameterless initializer.
- Hidden stored properties are allowed when an accessible matching initializer handles them.
- Initializer-level actor attributes are unsupported; declare actor isolation on the annotated type instead.
- Nested declarations must have accessible ancestors. Generated access is capped by the enclosing types.
- Generic fake fields must have constructible defaults, such as `Value?` or `[Value]`. A bare `Value` has no automatic default.
- Required nested defaults must not form a construction cycle. Optional, collection, and closure defaults can break a cycle.
- Protocol inheritance must be readable in the same target, apart from supported marker protocols.
- Associated types, protocol-level constraints, overloaded requirements, static requirements, subscripts, and generic thrown-error types are unsupported.
- Annotations inside conditional blocks, extensions containing nested declarations, or function bodies are unsupported.
- A throwing fake cannot initialize a nonthrowing double's stored default.

Use explicit overrides for values that must satisfy application-specific validation. Mercury can derive a value from a field's type; it cannot infer business rules.

## Development

```sh
swift test
python3 Scripts/verify-generated.py --products "$(swift build --show-bin-path)"
swift build -c release
swift test --sanitize thread --filter ConcurrentDoubleBehaviourTests
```

The consumer checks compile actual generated code, execute Debug fixtures, verify missing-response failures, and check Release signatures and double removal. CI runs the suite on Swift 6.3 and Swift 6.4.
