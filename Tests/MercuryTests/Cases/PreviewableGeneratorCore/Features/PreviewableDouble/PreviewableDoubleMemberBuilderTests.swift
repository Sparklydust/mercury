//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import PreviewableGeneratorCore
import Testing

struct PreviewableDoubleMemberBuilderTests {

  @Test(arguments: [
    ("@PreviewableDouble protocol Service: Sendable { init(value: Int) }", "previewableRequireSendable(value)"),
    ("@PreviewableDouble protocol Service { init(_ handler: () -> Void) }", ".append([])"),
    ("@MainActor @PreviewableDouble protocol Service { nonisolated init(value: Int) }", "nonisolated init(value: Int)")
  ])
  func initializer_supportedArguments_preservesRecordingContract(
    _ source: String,
    _ expected: String
  ) throws {
    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "Initializer witnesses must preserve isolation and omit function records.")
  }

  @Test
  func initializer_localArgumentIsUnnamed_diagnosticExplainsRequirement() {
    let source = "@PreviewableDouble protocol Service { init(_ _: Int) }"
    let expected = "requires a named local parameter"

    let result = generatorDiagnosticMessage(for: source)

    #expect(result?.contains(expected) == true, "Unnamed arguments cannot be recorded.")
  }
}
