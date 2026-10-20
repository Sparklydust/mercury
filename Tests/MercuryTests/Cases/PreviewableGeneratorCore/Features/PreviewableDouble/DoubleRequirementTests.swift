//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

struct DoubleRequirementTests {

  @Test(arguments: [
    (
      """
      @PreviewableDouble protocol Service { var first: Int { get }; var second: Int { get } }
      """,
      "var second: Int"
    ),
    (
      """
      protocol Base { subscript(_ index: Int) -> Int { get } }
      @PreviewableDouble protocol Service: Base { subscript(_ index: Int) -> Int { get set } }
      """,
      "set(newValue)"
    ),
    (
      """
      @PreviewableDouble protocol Service { func load<Value: Collection & Sendable>(_ value: Value) -> Int where Value.Element: Sendable }
      """,
      "where Value.Element: Sendable"
    ),
    (
      """
      @MainActor @PreviewableDouble protocol Service { nonisolated func load() -> Int }
      """,
      "nonisolated func load()"
    ),
    (
      """
      @PreviewableDouble protocol Service { subscript(_ index: Int) -> Int { get }; subscript(name name: String) -> String { get } }
      """,
      "subscript(name name: String)"
    )
  ])
  func requirements_equivalentDeclarations_preserveWitnesses(
    _ source: String,
    _ expected: String
  ) throws {
    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(
      result.contains(expected),
      "Canonical requirement collection must preserve overloads, writable witnesses, and isolation."
    )
  }
}
