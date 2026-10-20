//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

struct DoubleStaticBuilderTests {

  @Test(arguments: [
    (
      """
      @PreviewableDouble public protocol Service: Sendable { static var count: Int { get set } }
      """,
      "public nonisolated static func withStaticStubs<Result>"
    ),
    (
      """
      @PreviewableDouble protocol Service: Sendable { static func make<Value: Sendable>(_ type: Value.Type) -> Value }
      """,
      "static var makeStub: PreviewableResponses"
    ),
    (
      """
      @MainActor @PreviewableDouble protocol Service { static func load() -> Int }
      """,
      "@MainActor\n  private final class _PreviewableStaticState"
    ),
    (
      """
      @PreviewableDouble protocol Service { @MainActor static func store(_ value: String) }
      """,
      "static var mainActorPassedParameters:"
    ),
    (
      """
      @PreviewableDouble protocol Service { static var count: Int { get set } }
      """,
      "_modify { yield &_previewableStaticState.countStub }"
    ),
    (
      """
      @PreviewableDouble protocol Service { static func load() -> Int; func load() -> Int }
      """,
      "self.loadStub"
    )
  ])
  func staticRequirements_scopeIsGenerated_preservesScopedStorage(
    _ source: String,
    _ expected: String
  ) throws {
    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(
      result.contains(expected),
      "Static generation must preserve the declared scope, isolation, and storage contract."
    )
  }
}
