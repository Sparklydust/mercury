//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import PreviewableGeneratorCore
import Testing

struct DoublePropertyRequirementMergerTests {

  @Test(arguments: [
    ("get async throws", "get async", true, false),
    ("get async", "get", false, false),
    ("get", "get async throws", false, false),
    ("get async throws(FirstFailure)", "get async throws(SecondFailure)", true, false),
    ("get async throws", "get async throws(FirstFailure)", true, true),
    ("get async throws(FirstFailure)", "get async throws", true, true)
  ])
  func inheritance_equivalentProperties_preservesCompatibleGetter(
    _ first: String,
    _ second: String,
    _ asynchronous: Bool,
    _ throwing: Bool
  ) throws {
    let source = """
      enum FirstFailure: Error { case failed }
      enum SecondFailure: Error { case failed }
      protocol First { var value: Int { \(first) } }
      protocol Second { var value: Int { \(second) } }
      @PreviewableDouble protocol Service: First, Second {}
      """
    let expected = [asynchronous, throwing]

    let generated = try PreviewableSourceGenerator.generate(from: [source])
    let result = [generated.contains("valueSpy:"), generated.contains("valueErrorStub:")]

    #expect(result == expected, "Inherited properties must use getter effects accepted by every base protocol.")
  }
}
