//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import PreviewableGeneratorCore
import Testing

struct DoubleTypeCanonicalizerTests {

  @Test(arguments: [
    """
    protocol Base { func load(_ value: [String: Int]) }
    @PreviewableDouble protocol Service: Base {
      func load(_ value: Swift.Dictionary<Swift.String, Swift.Int>)
    }
    """,
    "@PreviewableDouble protocol Service { func load(_ value: ()) }",
    "@PreviewableDouble protocol Service { func load(_ value: any Codable & Sendable) }"
  ])
  func requirements_compoundTypes_preserveSingleWitness(_ source: String) throws {
    let expected = 1

    let generated = try PreviewableSourceGenerator.generate(from: [source])
    let result = generated.components(separatedBy: "func load(").count - 1

    #expect(result == expected, "Equivalent compound types must produce one witness.")
  }
}
