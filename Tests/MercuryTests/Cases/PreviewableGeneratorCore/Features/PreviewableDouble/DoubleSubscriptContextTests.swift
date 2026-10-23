//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import PreviewableGeneratorCore
import Testing

struct DoubleSubscriptContextTests {

  @Test(arguments: [
    (
      """
      @PreviewableDouble protocol Service { subscript(_ newValue: Int) -> String { get set } }
      """,
      "set(_newValue)"
    ),
    (
      """
      @PreviewableDouble protocol Service { subscript(_ newValue: Int, _ _newValue: String) -> Int { get set } }
      """,
      "set(__newValue)"
    ),
    (
      """
      @PreviewableDouble protocol Service { subscript<Value: Sendable>(_ type: Value.Type) -> Value { get } }
      """,
      "self.subscriptStub.require("
    ),
    (
      """
      @MainActor @PreviewableDouble protocol Service { nonisolated subscript(_ index: Int) -> String { get } }
      """,
      "private nonisolated func _previewableResolve_subscript"
    ),
    (
      """
      @PreviewableDouble protocol Service { subscript<Value>(_ values: [Value]) -> Int where Value: Sendable { get } }
      """,
      "where Value: Sendable"
    ),
    (
      """
      enum Failure: Error { case failed }
      @PreviewableDouble protocol Service { subscript(_ index: Int) -> Int { get throws(Failure) } }
      """,
      "get throws(Failure)"
    )
  ])
  func subscript_responseIsGenerated_preservesTypedResolution(
    _ source: String,
    _ expected: String
  ) throws {
    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(
      result.contains(expected),
      "Typed response resolution must preserve generic constraints and avoid setter argument shadowing."
    )
  }
}
