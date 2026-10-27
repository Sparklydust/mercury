//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

/// Supplies the value generated fakes and doubles use for a type the generator cannot inspect.
///
/// Mercury provides conformances for supported scalar and Foundation types. Imported aliases use their
/// underlying type's conformance. Missing defaults are diagnosed when generated source is compiled.
///
/// Declare each external type's conformance once in the application. Use `@retroactive` when the type and protocol
/// are owned outside the current package. Share the conformance when several targets need it.
/// Types declared in the consuming module use `@PreviewableFake` instead.
///
/// ```swift
/// extension CLAccuracyAuthorization: @retroactive PreviewableSynthesizable {
///   public static var previewableDefault: CLAccuracyAuthorization { .fullAccuracy }
/// }
/// ```
public protocol PreviewableSynthesizable {

  /// The value used when the caller supplies no override.
  /// Repeated reads may return different values, such as newly generated UUIDs.
  static var previewableDefault: Self { get }
}
