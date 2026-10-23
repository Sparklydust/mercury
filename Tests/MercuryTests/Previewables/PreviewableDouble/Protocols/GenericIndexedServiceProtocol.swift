//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// Returns values keyed by the requested concrete generic type.
@PreviewableDouble
protocol GenericIndexedServiceProtocol: Sendable {
  subscript<Value: Sendable>(_ type: Value.Type) -> Value { get }
}
