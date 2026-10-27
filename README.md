# Mercury

**Generate Swift doubles and sample data for tests, previews, and development.**

Annotate a protocol with `@PreviewableDouble` or a model with `@PreviewableFake`. Mercury generates configurable responses, error stubs, call recording, and model factories during the build.

Use the same generated types to test a feature, preview its UI, or develop it before a backend is available.

[Get started](#installation) · [Example](#one-feature-three-uses) · [Usage reference](Documentation/Usage.md) · [Contributing](Documentation/Development.md) · [MIT license](LICENSE)

## What Mercury generates

| Annotation | Generated API | Use |
| --- | --- | --- |
| `@PreviewableDouble` on `ProfileServiceProtocol` | `ProfileServiceDouble` | Replace a dependency and control its behavior. |
| `@PreviewableFake` on `Profile` | `Profile.fake(...)` | Create sample values with defaults and selected overrides. |

A **double** replaces a real dependency. Its role depends on how you use it:

| Role | Purpose | With Mercury |
| --- | --- | --- |
| Dummy | Fill a dependency that the scenario does not call. | Inject a fresh double. |
| Stub | Return a chosen value or error. | Configure `loadProfileStub` or `loadProfileErrorStub`. |
| Spy | Record calls and arguments for inspection. | Read `calledMethods` and `passedParameters`. |
| Mock | Verify an expected interaction. | Assert against the double's recorded calls in Swift Testing. |

Mercury combines these roles in one generated type. You write the expectations; Mercury records the interactions. A **model fake** is sample data created by `.fake(...)`.

## Requirements

- Swift 6.4 or later.
- An Apple Silicon Mac, or Linux using source-built tools.
- Apple deployment targets: iOS 27, macOS 27, tvOS 27, visionOS 27, and watchOS 27 or later.

SwiftUI examples require an Apple platform. See [validation scope](Documentation/Usage.md#validation-scope) for the platforms and workloads currently verified.

Mercury also works in Vapor and other server-side Swift projects on Linux. Add the library and build plugin to the server target containing the annotated types; generated doubles and fakes are available in Debug builds, including tests.

## Installation

### Xcode

1. Add `https://github.com/Sparklydust/mercury` through **File → Add Package Dependencies…**.
2. Add the **Mercury** library to the target containing your annotated types.
3. In that target's **Build Phases → Run Build Tool Plug-ins**, add **PreviewableBuildToolPlugin**.
4. Import `Mercury` in annotated files and build. Approve the plugin and macros if prompted.

Apply the same setup to each target declaring annotations. If the types live in your app or feature target, tests import that target to use its generated types.

### Swift Package Manager

Add Mercury to the package dependencies. This example tracks `main`; use a published version tag when one is available.

```swift
.package(url: "https://github.com/Sparklydust/mercury.git", branch: "main")
```

Add the library and plugin to each target declaring annotations:

```swift
.target(
  name: "YourFeature",
  dependencies: [.product(name: "Mercury", package: "mercury")],
  plugins: [.plugin(name: "PreviewableBuildToolPlugin", package: "mercury")]
)
```

The plugin generates and compiles `Previewables.generated.swift`. You do not maintain that file.

## One feature, three uses

Keep each type in its own file. This example uses a model, a service protocol, and a consumer that receives the service through its initializer.

**Profile.swift**

```swift
import Mercury

@PreviewableFake
struct Profile: Sendable {
  let name: String
}
```

**ProfileServiceProtocol.swift**

```swift
import Mercury

@PreviewableDouble
protocol ProfileServiceProtocol: Sendable {
  func loadProfile() async throws -> Profile
}
```

**ProfileTitle.swift**

```swift
struct ProfileTitle {
  let service: any ProfileServiceProtocol

  func title() async throws -> String {
    try await service.loadProfile().name
  }
}
```

Mercury generates `ProfileServiceDouble`, its `loadProfileStub` response, and `Profile.fake(name:)` with a default argument.

### Tests: control responses

In your test target, import the module containing these types, then use Swift Testing:

```swift
import Testing

@Test
func title_profileLoads_returnsConfiguredName() async throws {
  let serviceDouble = ProfileServiceDouble()
  serviceDouble.loadProfileStub = .fake(name: "Alex")
  let sut = ProfileTitle(service: serviceDouble)
  let expected = "Alex"

  let result = try await sut.title()

  #expect(result == expected)
}
```

### Tests: verify interactions

Use the same double as a spy and assert the expected interaction:

```swift
@Test
func title_profileIsRequested_callsServiceOnce() async throws {
  let serviceDouble = ProfileServiceDouble()
  let sut = ProfileTitle(service: serviceDouble)
  let expected = ["loadProfile()"]

  _ = try await sut.title()
  let result = serviceDouble.calledMethods

  #expect(result == expected)
}
```

`passedParameters` records non-closure arguments. Use a fresh double for every test so responses and call history remain independent.

### Tests: observe async work

Each async method gets a spy, such as `loadProfileSpy`. Its observer runs after call recording and before the captured response or error is delivered. Use it to inspect intermediate state, including a consumer's loading flag.

```swift
@Test
@MainActor
func title_requestIsInProgress_serviceCallIsRecorded() async throws {
  let serviceDouble = ProfileServiceDouble()
  let sut = ProfileTitle(service: serviceDouble)
  var observed: [String]?
  serviceDouble.loadProfileSpy.observe { [weak serviceDouble] in
    observed = serviceDouble?.calledMethods
  }
  let expected = ["loadProfile()"]

  _ = try await sut.title()
  let result = observed

  #expect(result == expected)
}
```

The observer inherits its creation context's actor. Capturing the value and asserting afterward also detects a missing invocation.

For tests that need control over completion order, use `pause()`, `waitForCall()`, and the returned call's `resume()`. Async computed properties and subscript getters support the same controls. See [async observation and pauses](Documentation/Usage.md#async-observation-and-pauses) for examples, timeouts, and cancellation behavior.

### Previews: inject sample data

**ProfileView.swift**

```swift
import SwiftUI

struct ProfileView: View {
  let service: any ProfileServiceProtocol
  @State private var title = "Loading…"

  var body: some View {
    Text(title)
      .task {
        do {
          title = try await ProfileTitle(service: service).title()
        } catch {
          title = "Unable to load profile"
        }
      }
  }
}
```

Build a preview with a configured double:

```swift
#if DEBUG
#Preview {
  let serviceDouble = ProfileServiceDouble()
  serviceDouble.loadProfileStub = .fake(name: "Alex")
  return ProfileView(service: serviceDouble)
}
#endif
```

### Development: work without a live service

Inject the double at your app's dependency setup while building the feature:

```swift
#if DEBUG
let serviceDouble = ProfileServiceDouble()
serviceDouble.loadProfileStub = .fake(name: "Development profile")
let profileView = ProfileView(service: serviceDouble)
#endif
```

For failure scenarios, set `loadProfileErrorStub` to an error. Use `loadProfileErrorsStub` for a queue of errors consumed before the persistent error. Replace the injected double with your real service when needed.

## Build behavior

Generated double classes, response configuration, call recording, and working fake factories are available under `#if DEBUG`. Guard development-only call sites with the same condition and keep `DEBUG` out of Release compilation conditions.

Release builds retain placeholder fake factories and protocol-typed preview accessors for type checking. Calling these placeholders traps. Generated double classes are unavailable in Release.

On Apple Silicon Macs, Mercury uses bundled generator and macro executables to avoid building SwiftSyntax in consumer builds. Linux builds the tools from source. These tools run during the build and are not embedded in your app.

## More capabilities

Mercury supports async and throwing methods, overloads, associated types, generic responses, property and subscript requirements, scoped static stubs, actor isolation, and defaults for types declared in other modules.

See the [usage reference](Documentation/Usage.md) for configuration examples, concurrency behavior, and current limitations. Unsupported declarations produce source diagnostics during generation.

## Contributing

Read the [development guide](Documentation/Development.md) for tests, CI checks, and bundled-tool updates. Keep changes focused, match the existing Swift style, and add behavior-focused tests when behavior changes.

## License

Mercury is available under the [MIT License](LICENSE). Third-party components retain their own licenses; the bundled SwiftSyntax license is included in the [artifact bundle](Artifacts/PreviewableGenerator.artifactbundle/licenses/SwiftSyntax-LICENSE.txt).
