//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import PreviewableGeneratorCore
import Testing

struct DoubleSubscriptBuilderTests {

  @Test(arguments: [
    (
      """
      @PreviewableDouble protocol Service { subscript(_ index: Int) -> String { get set } }
      """,
      "set(newValue)"
    ),
    (
      """
      @PreviewableDouble protocol Service { subscript(name name: String) -> Int { get } }
      """,
      "_previewableResolve_subscript(name: name)"
    ),
    (
      """
      @PreviewableDouble protocol Service { subscript(_ index: Int) -> String { get async throws } }
      """,
      "get async throws"
    ),
    (
      """
      @PreviewableDouble protocol Service { static subscript(_ index: Int) -> String { get set } }
      """,
      "static subscript"
    ),
    (
      """
      @PreviewableDouble protocol Service { subscript(_ predicate: () -> Bool) -> Int { get } }
      """,
      "_previewableResolve_subscript(predicate)"
    )
  ])
  func subscript_requirementIsGenerated_preservesAccessorContract(
    _ source: String,
    _ expected: String
  ) throws {
    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(
      result.contains(expected),
      "The subscript must preserve accessor effects, dispatch, and index argument forwarding."
    )
  }
}
