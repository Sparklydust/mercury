# Usage reference

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
let expected = "Alex"

let result = try await serviceDouble.name(for: 42)

#expect(result == expected)
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
let expected = "ready"

let result = try await serverDouble.make(for: String.self)

#expect(result == expected)
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

Parameters have repeatable defaults and accept overrides. Defaults cover common scalar types, optionals, collections, simple enums, annotated types, and external types conforming to `PreviewableSynthesizable`. Computed properties and initialized constants are excluded. Override defaults when application validation requires specific values.

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

### Defaults for external types

Without an annotation, a type declared outside the module defaults to `Type.previewableDefault`. Supply it by conforming the type to `PreviewableSynthesizable` in the module that uses it:

```swift
extension CLAccuracyAuthorization: @retroactive PreviewableSynthesizable {
  public static var previewableDefault: CLAccuracyAuthorization { .fullAccuracy }
}
```

Mercury conforms `Bool`, `String`, `Character`, the integer and floating-point types, `CGFloat`, `Data`, `Date`, `UUID`, `URL`, and `Decimal`, so an alias another module declares for one of them, such as `CLLocationDistance`, needs nothing more. A generic type conforms conditionally on its arguments:

```swift
extension Box: @retroactive PreviewableSynthesizable where Element: PreviewableSynthesizable {
  public static var previewableDefault: Box<Element> { Box(element: Element.previewableDefault) }
}
```

A missing conformance is a compiler error in the generated source, not a trap at runtime. An extension annotated with `parameters:` keeps its `fake()` factory as the default, and optionals and collections keep `nil` and empty without a conformance. Existentials such as `any Error` or `Codable` cannot conform, and `Never` has no value, so the generator rejects both. Double stubs use the same defaults.

## Previews and Release builds

Use `ProfileServiceDouble.preview` for a shared preview instance. It retains state between accesses.

Non-Sendable and generic doubles return a fresh instance from `.preview`. The global accessor also returns a fresh instance for non-Sendable doubles. These accessors are nonisolated and require no additional annotations. Keep the returned instance when configuring stubs before injection.

Double classes, stub and spy storage, and fake construction compile only under `#if DEBUG`. Keep `DEBUG` out of Release compilation conditions.

Release retains placeholder `fake()` factories and protocol-typed preview accessors so preview code can type-check. Calling these placeholders traps; fake calls are not rejected at compile time. Keep their use in tests or previews, or guard call sites with `#if DEBUG`.

The bundled generator and macro executables run on the build machine and are not embedded in the application.

## Async observation and pauses

Async methods, static async methods, async computed getters, and async subscript getters expose a `<member>Spy`. Overloads use the same allocated name as their stubs, such as `loadIdIntSpy`. Synchronous members retain their existing API.

**Observe an intermediate value.** In a `@MainActor` test suite, keep the SUT and generated double in the fixture, as with other dependency doubles. Here, `sut.load()` sets `isLoading` while awaiting `serviceDouble.load()`.

```swift
@Test
func load_requestIsInProgress_isLoadingIsTrue() async {
  var observed: Bool?
  serviceDouble.loadSpy.observe { [weak sut] in observed = sut?.isLoading }
  let expected = true

  await sut.load()
  let result = observed

  #expect(result == expected, "Loading must be visible while the dependency is executing.")
}
```

Observation is nonthrowing and retains the closure's actor isolation. The optional capture starts as `nil`, so this assertion fails if the dependency is never called. Observers stay installed until replaced or removed with `observe(nil)`. Use weak captures when the observed object retains the double.

**Pause only when completion timing matters.** The same fixture can hold a request open without sleeps or polling:

```swift
@Test
func load_requestIsPaused_isLoadingIsTrue() async throws {
  serviceDouble.loadSpy.pause()
  let expected = true

  let operation = Task { await sut.load() }
  defer { operation.cancel() }
  let call = try await serviceDouble.loadSpy.waitForCall()
  let result = sut.isLoading
  call.resume()
  await operation.value

  #expect(result == expected, "Loading must remain visible until the invocation is resumed.")
}
```

Each invocation receives its own handle. Resume calls individually to test overlapping requests in a chosen order. `spy.resume()` releases all current pauses and stops pausing future calls. Repeated resume calls are harmless. `pause()` affects subsequent invocations.

The response, persistent error, and selected queued error are resolved under the double's lock before observation. Later stub changes affect subsequent invocations; an already captured reference still refers to the same object. Observers and pauses run outside the lock. Queued errors retain priority over the persistent error stub.

The spy adds no suspension of its own: a call suspends only when its observer does or a pause holds it. No other work on the caller's actor runs during a call that is neither observed nor paused.

`waitForCall()` consumes the next unclaimed invocation in arrival order, even if it has already finished. Observation does not consume this queue. Waiting defaults to five seconds; pass `timeout:` to change it. Expiry throws `PreviewableAsyncSpyError.timedOut`; cancelling the waiting task throws `CancellationError`. An expired wait does not resume or cancel the invocation.

Cancelling an invoking task releases its pause and then delivers its captured response or configured error. This preserves nonthrowing, typed-throwing, and `rethrows` contracts. Observer closures remain responsible for cooperating with cancellation if they perform their own asynchronous work.

**Async computed properties** use the property name for configuration and observation:

```swift
@PreviewableDouble
protocol ProfileStoreProtocol: Sendable {
  var profile: Profile { get async throws }
}

let storeDouble = ProfileStoreDouble()
storeDouble.profileStub = .fake(name: "Alex")
let profile = try await storeDouble.profile
```

This getter also exposes `profileSpy`, `profileErrorStub`, and `profileErrorsStub`, and records reads as `profile.get`. Nonthrowing getters omit the error stubs. Swift's async properties are read-only computed getters; stored properties and setters cannot be declared async.

Static spies belong to the existing `withStaticStubs` scope, alongside their responses and recordings. Inheriting child tasks share the scope; nested scopes remain independent. Generated spies are available with their doubles in Debug builds.

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

