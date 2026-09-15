//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Mercury

typealias CanonicalIdentifier = Int

/// Supplies an inherited signature spelled through a local alias.
protocol CanonicalServiceProtocol {
  func load(id: CanonicalIdentifier) -> String
}

/// Exercises equivalent inherited signatures and independent overload responses.
@PreviewableDouble
protocol OverloadedServiceProtocol: CanonicalServiceProtocol, Sendable {
  func load(id: Swift.Int) -> String
  func load(id: String) -> String
  func load(name: String) -> String
}

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

/// Binds an associated response to a concrete scalar default.
@PreviewableDouble
protocol ConcreteStoreProtocol {
  associatedtype Element where Element == String
  func value() -> Element
}

/// Exercises transitive same-type bindings without leaving a redundant generic parameter.
@PreviewableDouble
protocol ConcreteChainProtocol where First == Second, Second == Third, Third == String {
  associatedtype First
  associatedtype Second
  associatedtype Third
  func value() -> First
}

/// Preserves a dependent element constraint across two associated types.
@PreviewableDouble
protocol CollectionStoreProtocol<Item, Items>: Sendable where Items.Element == Item {
  associatedtype Item: Sendable
  associatedtype Items: Collection & Sendable
  func values() -> Items
  func first() -> Item
}

/// An index that supports recording without supporting hash-based lookup.
struct NonHashableIndex: Sendable {
  let value: Int
}

/// Exercises typed and explicitly labeled subscript overloads.
@PreviewableDouble
protocol IndexedServiceProtocol: Sendable {
  subscript(_ index: NonHashableIndex) -> String { get set }
  subscript(name name: String) -> Int { get }
}

/// Provides an asynchronous throwing getter for subscript validation.
@PreviewableDouble
protocol AsyncIndexedServiceProtocol: Sendable {
  subscript(_ index: Int) -> String { get async throws }
}

/// Returns values keyed by the requested concrete generic type.
@PreviewableDouble
protocol GenericIndexedServiceProtocol: Sendable {
  subscript<Value: Sendable>(_ type: Value.Type) -> Value { get }
}

/// Identifies queue entries independently of concurrent caller scheduling.
enum ScopedFailure: Error, Equatable {
  case numbered(Int)
}

/// A mutable actor-confined payload used to verify static recording isolation.
@MainActor
final class ScopedPayload {
  var value = 0
}

/// Keeps static arguments and responses on the protocol actor.
@MainActor
@PreviewableDouble
protocol ActorStaticServiceProtocol {
  static func store(_ value: ScopedPayload) -> ScopedPayload?
}
