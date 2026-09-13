import Foundation
import Mercury

@PreviewableDouble
protocol ConcurrentServiceProtocol: Sendable {
  func load(key: Int) async throws -> String
  func make<Value: Codable & Sendable>(_ type: Value.Type) async throws -> Value
}

@PreviewableDouble
protocol ChildServiceProtocol: Sendable {
  var count: Int { get set }
}

@PreviewableDouble
protocol ParentServiceProtocol: Sendable {
  var child: any ChildServiceProtocol { get }
}

enum ConstructionError: Error { case invalid }

@PreviewableFake
struct CheckedValue {
  let count: Int

  init(count: Int) throws {
    guard count > 0 else { throw ConstructionError.invalid }
    self.count = count
  }
}

@PreviewableFake
struct ThrowingContainer {
  let value: CheckedValue
}

@PreviewableFake
struct ObservedValue {
  var count: Int { didSet {} }
}

enum FirstNamespace {
  enum Kind { case first }

  @PreviewableFake
  struct Model { let kind: Kind }
}

enum SecondNamespace {
  enum Kind { case second }

  @PreviewableFake
  struct Model { let kind: Kind }
}
