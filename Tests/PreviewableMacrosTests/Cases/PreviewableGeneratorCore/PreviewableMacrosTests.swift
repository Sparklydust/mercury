import PreviewableGeneratorCore
import SwiftSyntaxMacroExpansion
import Testing
@testable import PreviewableMacrosPlugin

@Suite
struct PreviewableMacrosTests {

  private let macroSpecs: [String: MacroSpec] = [
    "PreviewableDouble": .init(type: PreviewableDoubleMacro.self),
    "PreviewableFake": .init(type: PreviewableFakeMacro.self)
  ]
  private let source = """
    import Foundation

    enum Mode {
      case ready
      case unavailable
    }

    @PreviewableDouble
    protocol ServiceProtocol {
      var state: Mode { get set }
      func load(id: Int) async throws -> [String]
    }

    @PreviewableFake
    struct Model {
      let value: String
    }

    @PreviewableFake
    final class ReferenceModel {
      var value = String()

      init() {}
    }
    """

  // MARK: - Previewable Double
  @Test
  func previewableDouble_declarationIsNotProtocol_diagnosticIsEmitted() {
    expectMacroExpansion(
      """
      @PreviewableDouble
      struct Service {}
      """,
      expandedSource: """
      struct Service {}
      """,
      diagnostics: [
        .init(
          message: "@PreviewableDouble can only be applied to a protocol",
          line: 1,
          column: 1
        )
      ],
      macroSpecs: macroSpecs
    )
  }

  // MARK: - Previewable Fake
  @Test
  func previewableFake_declarationIsEnum_diagnosticIsEmitted() {
    expectMacroExpansion(
      """
      @PreviewableFake
      enum Model {}
      """,
      expandedSource: """
      enum Model {}
      """,
      diagnostics: [
        .init(
          message: "@PreviewableFake can only be applied to a structure or class",
          line: 1,
          column: 1
        )
      ],
      macroSpecs: macroSpecs
    )
  }

  @Test
  func previewableFake_declarationHasStoredProperties_expansionIsAccepted() {
    expectMacroExpansion(
      """
      @PreviewableFake
      struct Model {
        let value: Int
      }
      """,
      expandedSource: """
      struct Model {
        let value: Int
      }
      """,
      macroSpecs: macroSpecs
    )
  }

  // MARK: - Generator
  @Test(arguments: [
    "#if DEBUG\n/// A test double for `ServiceProtocol`.",
    "/// - Important: Available only in Debug builds.",
    "// Mock values",
    "// Preview value",
    "// Spy values",
    "// Protocol requirements",
    "/// The shared double used by previews.",
    "/// The protocol method names invoked on this double.",
    "private(set) var calledMethods: [String] = []",
    "private(set) var passedParameters: [String: [Any?]] = [:]",
    "var stateStub: Mode = Mode.ready",
    "var state: Mode {\n    get { stateStub }\n    set { stateStub = newValue }\n  }",
    "var loadErrorStub: (any Error)?",
    "var loadStub: [String] = []",
    "passedParameters[#function] = [id]",
    "/// The shared `ServiceDouble` for SwiftUI preview dependency injection.",
    "nonisolated var serviceDouble: any ServiceProtocol",
    "serviceDouble is unavailable outside Debug builds and SwiftUI previews"
  ])
  func generator_protocolIsAnnotated_expectedDoubleMemberIsGenerated(
    _ expected: String
  ) throws {
    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(
      result.contains(expected),
      "Generated source must contain `\(expected)`."
    )
  }

  @Test(arguments: [
    ") -> Model {\n    .init(",
    "convenience init(\n    value: String",
    ") -> ReferenceModel {\n    .init("
  ])
  func generator_fakeIsAnnotated_expectedFactoryMemberIsGenerated(
    _ expected: String
  ) throws {
    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(
      result.contains(expected),
      "Generated source must contain `\(expected)`."
    )
  }

  @Test
  func generator_fakeHasTwoStrings_defaultsAreDistinctLoremStrings() throws {
    let generated = try PreviewableSourceGenerator.generate(from: [source])
    let defaults = generated.components(separatedBy: "\n").filter {
      $0.contains("value: String = \"")
    }

    let result = defaults.count == 2
      && Set(defaults).count == 2
      && !generated.contains("LoremIpsum")

    #expect(result, "String defaults must be distinct generated LoremSwiftum strings.")
  }

  @Test
  func generator_fakeDefaults_areDistinctAndNonZero() throws {
    let generated = try PreviewableSourceGenerator.generate(from: [
      """
      @PreviewableFake
      struct FakeDefaults {
        let firstNumber: Int
        let secondNumber: Double
        let title: String
        let detail: String
        let firstURL: URL
        let secondURL: URL
        let firstID: UUID
        let secondID: UUID
      }
      """
    ])
    let stringDefaults: [String] = generated.components(separatedBy: "\n").compactMap { line in
      guard line.contains(": String = \"") else { return nil }
      let components = line.split(separator: "\"")
      guard components.count > 1 else { return nil }
      return String(components[1])
    }
    let wordCounts = stringDefaults.map { $0.split(separator: " ").count }
    let usesDistinctURLs = generated.contains(
      "firstURL: URL = URL(string: \"https://fake.url.com/1\")!"
    ) && generated.contains(
      "secondURL: URL = URL(string: \"https://fake.url.com/2\")!"
    )
    let usesDistinctUUIDs = generated.contains(
      "firstID: UUID = UUID(uuidString: \"00000000-0000-0000-0000-000000000001\")!"
    ) && generated.contains(
      "secondID: UUID = UUID(uuidString: \"00000000-0000-0000-0000-000000000002\")!"
    )
    let result = generated.contains("firstNumber: Int = 1")
      && generated.contains("secondNumber: Double = 2")
      && usesDistinctURLs
      && usesDistinctUUIDs
      && Set(stringDefaults).count == 2
      && Set(wordCounts) == Set([2, 3])

    #expect(result, "Fake defaults must use distinct numbers, URLs, UUIDs, and short LoremSwiftum strings.")
  }

  @Test
  func generator_fakeIsBuiltOutsideDebug_factoryTerminatesWithoutValues() throws {
    let generated = try PreviewableSourceGenerator.generate(from: [source])

    let releaseSource = generated
      .components(separatedBy: "#else\n")
      .dropFirst()
      .first?
      .components(separatedBy: "#endif")
      .first
    let result = releaseSource?.contains("extension Model") == true
      && releaseSource?.contains("value: String = { () -> String in preconditionFailure(") == true
      && releaseSource?.contains("preconditionFailure(\"Model.fake(...) is unavailable") == true
      && releaseSource?.contains(".init(") == false

    #expect(result, "Release fake factories must terminate without constructing preview values.")
  }

  @Test(arguments: [
    "servicePreview",
    "func serviceDouble(",
    "func previewable()"
  ])
  func generator_protocolIsAnnotated_obsoleteAPIIsNotGenerated(
    _ forbidden: String
  ) throws {
    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(
      !result.contains(forbidden),
      "Generated source must not contain `\(forbidden)`."
    )
  }
}
