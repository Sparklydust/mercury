//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

struct DefaultAliasResolutionTests {

  @Test(arguments: [
    ("typealias Count = Int", "Count", "1"),
    ("typealias Count = Int\ntypealias Total = Count", "Total", "1"),
    ("enum Domain { typealias Count = Int }", "Domain.Count", "1"),
    ("typealias Values = [Int]", "Values", "[]"),
    ("typealias Value = Int?", "Value", ".none"),
  ])
  func generator_fakeFieldUsesAlias_defaultMatchesUnderlyingType(
    _ declaration: String, _ type: String, _ expected: String
  ) throws {
    let source = declaration + "\n@PreviewableFake struct Model { let value: \(type) }"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains("value: \(type) = \(expected)"), "Aliases must preserve their factory parameter type.")
  }

  @Test
  func generator_aliasIsShadowed_defaultUsesDeclarationScope() throws {
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

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains("count: Domain.Count = 1"), "Alias targets must resolve in the alias's declaration scope.")
  }

  @Test
  func generator_fakeFieldUsesClosureAlias_parameterEscapes() throws {
    let source = "typealias Action = () -> Int\n@PreviewableFake struct Model { let action: Action }"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains("action: @escaping Action = { 1 }"), "An aliased closure must be storable by the factory.")
  }

  @Test(arguments: [
    ("typealias A = B\ntypealias B = A\n@PreviewableFake struct Model { let value: A }", "cyclic type alias"),
    (
      "typealias Next = Model\n@PreviewableFake final class Model { var next: Next; init() { fatalError() } }",
      "recursive default construction"
    ),
  ])
  func generator_aliasFormsCycle_diagnosticExplainsFailure(_ source: String, _ expected: String) {
    let result = generatorDiagnosticMessage(for: source)

    #expect(result?.contains(expected) == true, "Alias expansion must reject cyclic construction.")
  }
}
