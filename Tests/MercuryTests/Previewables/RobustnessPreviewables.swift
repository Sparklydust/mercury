import Foundation
import Mercury

/// Exercises concurrent calls and responses indexed by generic return type.
@PreviewableDouble
protocol ConcurrentServiceProtocol: Sendable {
  func load(key: Int) async throws -> String
  func make<Value: Codable & Sendable>(_ type: Value.Type) async throws -> Value
}

/// Provides mutable nested state for double independence checks.
@PreviewableDouble
protocol ChildServiceProtocol: Sendable {
  var count: Int { get set }
}

/// Exercises eager construction of a fresh nested double.
@PreviewableDouble
protocol ParentServiceProtocol: Sendable {
  var child: any ChildServiceProtocol { get }
}

/// The validation failure used by throwing fake fixtures.
enum ConstructionError: Error { case invalid }

/// Exercises a throwing initializer that accepts only positive counts.
@PreviewableFake
struct CheckedValue {
  let count: Int

  init(count: Int) throws {
    guard count > 0 else { throw ConstructionError.invalid }
    self.count = count
  }
}

/// Exercises propagation of a nested factory throwing effect.
@PreviewableFake
struct ThrowingContainer {
  let value: CheckedValue
}

/// Exercises recognition of a stored property with an observer.
@PreviewableFake
struct ObservedValue {
  var count: Int { didSet {} }
}

/// Provides one lexical scope for same-named nested fake types.
enum FirstNamespace {
  enum Kind { case first }

  @PreviewableFake
  struct Model { let kind: Kind }
}

/// Provides a second lexical scope with a distinct enumeration default.
enum SecondNamespace {
  enum Kind { case second }

  @PreviewableFake
  struct Model { let kind: Kind }
}
