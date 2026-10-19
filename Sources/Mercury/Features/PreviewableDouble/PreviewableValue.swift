//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

/// Distinguishes an unconfigured response from a configured optional nil.
@_spi(Generated)
public enum PreviewableValue<Value> {
  case unconfigured
  case configured(Value)

  /// Returns the configured response or identifies the stub that needs configuration.
  /// - Parameter name: The generated stub name reported on failure.
  public func require(_ name: String) -> Value {
    guard case .configured(let value) = self else {
      preconditionFailure("Missing Previewable response for \(name)")
    }
    return value
  }
}

extension PreviewableValue: Sendable where Value: Sendable {}
