//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// Combines associated responses, overloads, static requirements, and subscripts.
@PreviewableDouble
protocol AssociatedStoreProtocol<Element>: Sendable {
  associatedtype Element: Sendable
  var current: Element? { get set }
  func value() -> Element
  func value(for id: Int) -> Element
  subscript(_ index: Int) -> Element { get set }
  static var revision: Int { get set }
  static func fetch(_ id: Int) async throws -> Element
  static func fetch(_ id: String) async throws -> Element
  static subscript(_ index: Int) -> Element { get set }
}
