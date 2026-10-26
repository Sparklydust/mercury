//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import PreviewableGeneratorCore
import Testing

struct DoubleAsyncPropertyBuilderTests {

  @Test(arguments: [
    ("var value: String { get async }", "get async {"),
    ("var value: String { get async throws }", "valueErrorStub"),
    ("var value: String { get async }", "let valueSpy: Mercury.PreviewableAsyncSpy"),
    ("static var value: String { get async }", "static var valueSpy: Mercury.PreviewableAsyncSpy"),
    ("var value: String { get async throws }", "[\"value.get\", default: []]"),
    ("subscript(_ index: Int) -> String { get async throws }", "await self.subscriptSpy.recordCall()")
  ])
  func asyncGetter_supportedRequirement_preservesEffectsAndSpy(
    _ member: String,
    _ expected: String
  ) throws {
    let source = "@PreviewableDouble protocol Service: Sendable { \(member) }"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "Async accessors must use the same control contract as methods.")
  }

  @Test
  func asyncGetter_errorStubNameIsAlreadyDeclared_reportsCollision() {
    let source = "@PreviewableDouble protocol Service { var value: Int { get async throws }; var valueErrorStub: Int { get } }"
    let expected = "'valueErrorStub' conflicts with a generated member"

    let result = generatorDiagnosticMessage(for: source)

    #expect(result?.contains(expected) == true, "Async getter error stubs must reserve their generated names.")
  }
}
