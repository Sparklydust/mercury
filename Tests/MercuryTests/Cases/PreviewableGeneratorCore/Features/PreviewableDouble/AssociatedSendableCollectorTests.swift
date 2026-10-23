//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import PreviewableGeneratorCore
import Testing

struct AssociatedSendableCollectorTests {

  @Test(arguments: [
    (
      """
      @PreviewableDouble protocol Service: Sendable { associatedtype Values: Collection & Sendable; func first() -> Values.Element }
      """,
      "_PreviewableValues.Element: Sendable"
    ),
    (
      """
      @PreviewableDouble protocol Service: Sendable { associatedtype Value; var value: Value { get } }
      """,
      "_PreviewableValue: Sendable"
    ),
    (
      """
      @MainActor @PreviewableDouble protocol Service { associatedtype Value; nonisolated func first() -> Value }
      """,
      "_PreviewableValue: Sendable"
    ),
    (
      """
      @MainActor protocol Base { static func load() -> Int }
      @PreviewableDouble protocol Service: Base {}
      """,
      "@MainActor\n  private final class _PreviewableStaticState"
    )
  ])
  func associatedRequirements_crossIsolation_preserveSendableComponents(
    _ source: String,
    _ expected: String
  ) throws {
    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(
      result.contains(expected),
      "Requirements crossing isolation must retain the necessary component Sendable constraints."
    )
  }
}
