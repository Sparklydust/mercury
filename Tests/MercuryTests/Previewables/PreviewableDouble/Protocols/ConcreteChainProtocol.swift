//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// Exercises transitive same-type bindings without leaving a redundant generic parameter.
@PreviewableDouble
protocol ConcreteChainProtocol where First == Second, Second == Third, Third == String {
  associatedtype First
  associatedtype Second
  associatedtype Third
  func value() -> First
}
