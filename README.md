# Mercury

`Mercury` is a shared Swift macro package. Its Previewable feature generates
dependency doubles and model fake factories from the production declarations
they mirror. The build-tool plugin writes them to derived sources, so consuming
projects contain no handwritten previewable files or source-level Debug
conditions.

Add the `Mercury` library and `PreviewableBuildToolPlugin` products to a target,
then import the public module where macros are declared:

```swift
import Mercury
```

## Doubles

```swift
@PreviewableDouble
protocol UnitSystemProtocol {
  var current: UnitSystemType { get }
  func update(to unit: UnitSystemType)
}
```

The generated `UnitSystemDouble` includes:

- Ready defaults and method return/error stubs.
- `calledMethods: [String]`.
- `passedParameters: [String: [Any?]]`.
- A shared `preview` instance.

Defaults are generated from the requirement type. Enums use their first case,
while standard Swift values use deterministic empty or zero values.

## Fakes

```swift
@PreviewableFake
final class CalculationModel {
  var speedEntry = String()
  var jouleResult = String()
}
```

This provides a ready `CalculationModel.fake()` while still allowing individual
values to be overridden. String defaults are distinct words generated at build
time by LoremSwiftum. Numeric defaults are `1`, collections are empty, Boolean
defaults are false, enums use their first case, and `Image` uses a system
placeholder.

## Factory

```swift
var unitSystem: Factory<any UnitSystemProtocol> {
  self { UnitSystemService() }
    .onPreview { unitSystemPreview }
}
```

FactoryKit's native `onPreview` modifier receives a generated computed preview
value. Direct access remains available, such as
`appStoragePreview.unitSystem = .metric`. The computed value resolves to the
shared double in Debug and traps with `preconditionFailure` otherwise. Double
declarations are Debug-only; fake factory signatures remain compiler-visible
because Swift type-checks `#Preview` bodies in Release, then are removed from the
linked production executable when unused.
