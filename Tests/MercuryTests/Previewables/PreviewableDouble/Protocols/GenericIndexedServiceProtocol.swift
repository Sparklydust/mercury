//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Mercury

/// Returns values keyed by the requested concrete generic type.
@PreviewableDouble
protocol GenericIndexedServiceProtocol: Sendable {
  subscript<Value: Sendable>(_ type: Value.Type) -> Value { get }
}
