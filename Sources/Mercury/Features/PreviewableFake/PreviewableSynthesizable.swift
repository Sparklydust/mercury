//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

/// Supplies the value generated fakes and doubles use for a type the generator cannot inspect.
///
/// The build tool reads only the current module, so a type declared elsewhere carries no constructible default.
/// Conformances below cover the standard library's primitives together with `Data`, `Date`, `UUID`, `URL` and
/// `Decimal`, which also resolves every alias another module declares for one of them. A type with no conformance
/// fails to compile in the generated source, so an unresolved default is a build error rather than a trap when the
/// value is read.
///
/// A type the module does not own conforms in the module that uses it, which Swift 6 requires to be marked
/// `@retroactive`, and a generic type conforms conditionally on its arguments. A type the module does own is
/// annotated with `@PreviewableFake` instead, so the generator builds it from its stored properties.
///
/// ```swift
/// extension CLAccuracyAuthorization: @retroactive PreviewableSynthesizable {
///   public static var previewableDefault: CLAccuracyAuthorization { .fullAccuracy }
/// }
/// ```
public protocol PreviewableSynthesizable {

  /// The value used when the caller supplies no override.
  static var previewableDefault: Self { get }
}

extension Bool: PreviewableSynthesizable {
  public static var previewableDefault: Bool { false }
}

extension String: PreviewableSynthesizable {
  public static var previewableDefault: String { .init() }
}

extension Character: PreviewableSynthesizable {
  public static var previewableDefault: Character { "a" }
}

extension Data: PreviewableSynthesizable {
  public static var previewableDefault: Data { .init() }
}

extension Date: PreviewableSynthesizable {
  public static var previewableDefault: Date { .init(timeIntervalSince1970: 0) }
}

extension UUID: PreviewableSynthesizable {
  public static var previewableDefault: UUID { .init() }
}

extension URL: PreviewableSynthesizable {
  public static var previewableDefault: URL { .init(string: "https://example.com")! }
}

extension Decimal: PreviewableSynthesizable {
  public static var previewableDefault: Decimal { .zero }
}

extension PreviewableSynthesizable where Self: BinaryInteger {
  public static var previewableDefault: Self { .zero }
}

extension PreviewableSynthesizable where Self: BinaryFloatingPoint {
  public static var previewableDefault: Self { .zero }
}

extension Int: PreviewableSynthesizable {}
extension Int8: PreviewableSynthesizable {}
extension Int16: PreviewableSynthesizable {}
extension Int32: PreviewableSynthesizable {}
extension Int64: PreviewableSynthesizable {}
extension UInt: PreviewableSynthesizable {}
extension UInt8: PreviewableSynthesizable {}
extension UInt16: PreviewableSynthesizable {}
extension UInt32: PreviewableSynthesizable {}
extension UInt64: PreviewableSynthesizable {}
extension Double: PreviewableSynthesizable {}
extension Float: PreviewableSynthesizable {}
#if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
extension Float16: PreviewableSynthesizable {}
#endif
extension CGFloat: PreviewableSynthesizable {}
