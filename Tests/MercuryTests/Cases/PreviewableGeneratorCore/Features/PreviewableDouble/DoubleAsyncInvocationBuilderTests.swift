//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import PreviewableGeneratorCore
import Testing

struct DoubleAsyncInvocationBuilderTests {

  @Test(arguments: [
    ("func load() async -> String", "let loadSpy: Mercury.PreviewableAsyncSpy"),
    ("func load() async throws -> String", "let response: Swift.Result<String, any Error>"),
    ("func refresh() async", "let response: Swift.Void"),
    ("func load() async -> String", "await self.loadSpy.recordCall()"),
    ("static func load() async -> String", "static var loadSpy: Mercury.PreviewableAsyncSpy"),
    ("func make<Value: Sendable>(_ type: Value.Type) async -> Value", "let makeSpy: Mercury.PreviewableAsyncSpy")
  ])
  func asyncMember_supportedSignature_generatesExpectedControl(
    _ member: String,
    _ expected: String
  ) throws {
    let source = "@PreviewableDouble protocol Service: Sendable { \(member) }"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "Async generation must preserve the member's snapshot and spy contract.")
  }

  @Test
  func synchronousMember_isGenerated_doesNotAddAsyncSpy() throws {
    let source = "@PreviewableDouble protocol Service { func load() -> String }"
    let expected = false

    let generated = try PreviewableSourceGenerator.generate(from: [source])
    let result = generated.contains("loadSpy")

    #expect(result == expected, "Synchronous members must retain their existing API.")
  }

  @Test
  func asyncMember_spyNameIsAlreadyDeclared_reportsCollision() {
    let source = "@PreviewableDouble protocol Service { func load() async; var loadSpy: Int { get } }"
    let expected = "'loadSpy' conflicts with a generated member"

    let result = generatorDiagnosticMessage(for: source)

    #expect(result?.contains(expected) == true, "Spy names must participate in generated-member validation.")
  }
}
