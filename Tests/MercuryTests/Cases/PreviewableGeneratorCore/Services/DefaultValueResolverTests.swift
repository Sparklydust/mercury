//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

struct DefaultValueResolverTests {

  private let compositionSource = """
    @PreviewableFake
    struct User {
      let identifier: Int
    }

    @PreviewableDouble
    protocol OtherProtocol {
      var flag: Bool { get }
    }

    @PreviewableDouble
    protocol ServiceProtocol {
      var onChange: () -> Void { get }
      var transform: (Int) -> String { get }
      var coordinate: (Int, Int) { get }
      var labelled: (latitude: Double, longitude: Double) { get }
      var delegate: any OtherProtocol { get }
      var outcome: Result<Int, any Error> { get }
      var owner: User { get }
      var payload: Data { get }
    }
    """

  private let fakeDefaultsSource = """
    @PreviewableFake
    struct FakeDefaults {
      let firstNumber: Int
      let secondNumber: Double
      let title: String
      let detail: String
      let firstURL: URL
      let secondURL: URL
      let firstID: UUID
      let secondID: UUID
      let firstDate: Date
      let secondDate: Date
    }
    """

  // MARK: - Resolver
  @Test(arguments: [
    "onChangeStub: () -> Void = { }",
    "transformStub: (Int) -> String = { _ in .init() }",
    "coordinateStub: (Int, Int) = (.zero, .zero)",
    "labelledStub: (latitude: Double, longitude: Double) = (latitude: .zero, longitude: .zero)",
    "delegateStub: any OtherProtocol = OtherDouble()",
    "outcomeStub: Result<Int, any Error> = .success(.zero)",
    "ownerStub: User = User.fake()",
    "payloadStub: Data = Data()"
  ])
  func resolver_requirementTypeIsComposite_defaultIsConstructible(_ expected: String) throws {
    let result = try PreviewableSourceGenerator.generate(from: [compositionSource])

    #expect(
      result.contains(expected),
      "Generated source must contain `\(expected)`."
    )
  }

  @Test
  func resolver_stringsBelongToDifferentFactories_defaultsAreDistinct() throws {
    let source = """
      @PreviewableFake
      struct Model { let value: String }

      @PreviewableFake
      final class ReferenceModel {
        var value = String()
        init() {}
      }
      """
    let expected = 2

    let generated = try PreviewableSourceGenerator.generate(from: [source])
    let defaults = generated.components(separatedBy: "\n").filter { $0.contains("value: String = \"") }
    let result = Set(defaults).count

    #expect(result == expected, "Separate factories must receive distinct string defaults.")
  }

  @Test(arguments: [
    "firstNumber: Int = 1",
    "secondNumber: Double = 2",
    "firstURL: URL = URL(string: \"https://fake.url.com/1\")!",
    "secondURL: URL = URL(string: \"https://fake.url.com/2\")!",
    "firstID: UUID = UUID(uuidString: \"00000000-0000-0000-0000-000000000001\")!",
    "secondID: UUID = UUID(uuidString: \"00000000-0000-0000-0000-000000000002\")!",
    "firstDate: Date = Date(timeIntervalSince1970: 1704067200)",
    "secondDate: Date = Date(timeIntervalSince1970: 1704153600)",
    "Generated `Date` values begin at `2024-01-01T00:00:00Z`"
  ])
  func resolver_fakeHasScalarFields_defaultsFollowAllocationOrder(_ expected: String) throws {
    let result = try PreviewableSourceGenerator.generate(from: [fakeDefaultsSource])

    #expect(result.contains(expected), "Generated defaults must contain `\(expected)`.")
  }

  @Test
  func resolver_fakeHasTwoStrings_defaultsAreDistinct() throws {
    let expected = 2
    let generated = try PreviewableSourceGenerator.generate(from: [fakeDefaultsSource])
    let result = Set(generatedStringDefaults(in: generated)).count

    #expect(result == expected, "Each string field must receive a distinct value.")
  }

  @Test
  func resolver_fakeHasTwoStrings_wordCountsFollowAllocationOrder() throws {
    let expected = [2, 3]
    let generated = try PreviewableSourceGenerator.generate(from: [fakeDefaultsSource])
    let result = generatedStringDefaults(in: generated).map { $0.split(separator: " ").count }

    #expect(result == expected, "Successive string allocations must contain two and three words.")
  }

  @Test
  func resolver_fakeHasStrings_obsoletePlaceholderIsAbsent() throws {
    let expected = "LoremIpsum"

    let result = try PreviewableSourceGenerator.generate(from: [fakeDefaultsSource])

    #expect(!result.contains(expected), "String defaults must not use the obsolete placeholder.")
  }

  @Test(arguments: [
    (
      """
      struct User { let id: Int }
      @PreviewableDouble
      protocol ServiceProtocol { var user: User { get } }
      """,
      "'User' must be annotated with @PreviewableFake"
    ),
    (
      """
      protocol OtherProtocol { var flag: Bool { get } }
      @PreviewableDouble
      protocol ServiceProtocol { var other: any OtherProtocol { get } }
      """,
      "'OtherProtocol' must be annotated with @PreviewableDouble"
    ),
    (
      """
      @PreviewableDouble
      protocol ServiceProtocol { var kind: String.Type { get } }
      """,
      "cannot synthesise a default for 'String.Type'"
    ),
    (
      """
      @PreviewableFake
      struct Box<Item> { let pair: (Item, Int) }
      """,
      "cannot synthesise a default for generic parameter 'Item'"
    ),
    (
      """
      @PreviewableFake
      struct Box<Item> { let value: Item }
      @PreviewableFake
      struct Holder { let box: Box<Int> }
      """,
      "cannot synthesise a default for generic parameter 'Item'"
    )
  ])
  func resolver_typeCannotBeDefaulted_diagnosticNamesTheFix(
    _ source: String,
    _ expected: String
  ) {
    let result = generatorDiagnosticMessage(for: source)

    #expect(
      result?.contains(expected) == true,
      "Expected a diagnostic containing `\(expected)`, got `\(result ?? "no diagnostic")`."
    )
  }

  @Test(arguments: [
    (
      """
      enum Status { case failed(Error); case idle }

      @PreviewableFake
      struct Session { var status: Status }
      """,
      "status: Status = Status.idle"
    ),
    (
      """
      enum Outer { enum Mode { case automatic } }

      @PreviewableFake
      struct Session { var mode: Outer.Mode }
      """,
      "mode: Outer.Mode = Outer.Mode.automatic"
    )
  ])
  func resolver_requirementIsEnumeration_defaultNamesACaseInScope(
    _ source: String,
    _ expected: String
  ) throws {
    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(
      result.contains(expected),
      "The default must name a parameterless case through its enclosing types, got `\(result)`."
    )
  }

  @Test(arguments: [
    ("typealias Count = Int", "Count", "1"),
    ("typealias Count = Int\ntypealias Total = Count", "Total", "1"),
    ("enum Domain { typealias Count = Int }", "Domain.Count", "1"),
    ("typealias Values = [Int]", "Values", "[]"),
    ("typealias Value = Int?", "Value", ".none")
  ])
  func resolver_fakeFieldUsesAlias_defaultMatchesUnderlyingType(
    _ declaration: String,
    _ type: String,
    _ value: String
  ) throws {
    let source = declaration + "\n@PreviewableFake struct Model { let value: \(type) }"
    let expected = "value: \(type) = \(value)"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "Aliases must preserve their factory parameter type.")
  }

  @Test
  func resolver_aliasIsShadowed_defaultUsesDeclarationScope() throws {
    let source = """
      typealias Value = String
      enum Domain {
        typealias Value = Int
        typealias Count = Value
        @PreviewableFake struct Model {
          typealias Value = Bool
          let count: Count
        }
      }
      """
    let expected = "count: Domain.Count = 1"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "Alias targets must resolve in the alias's declaration scope.")
  }

  @Test
  func resolver_fakeFieldUsesClosureAlias_parameterEscapes() throws {
    let source = "typealias Action = () -> Int\n@PreviewableFake struct Model { let action: Action }"
    let expected = "action: @escaping Action = { 1 }"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "An aliased closure must be storable by the factory.")
  }

  @Test(arguments: [
    ("typealias A = B\ntypealias B = A\n@PreviewableFake struct Model { let value: A }", "cyclic type alias"),
    (
      "typealias Next = Model\n@PreviewableFake final class Model { var next: Next; init() { fatalError() } }",
      "recursive default construction"
    )
  ])
  func resolver_aliasFormsCycle_diagnosticExplainsFailure(_ source: String, _ expected: String) {
    let result = generatorDiagnosticMessage(for: source)

    #expect(result?.contains(expected) == true, "Alias expansion must reject cyclic construction.")
  }
}
