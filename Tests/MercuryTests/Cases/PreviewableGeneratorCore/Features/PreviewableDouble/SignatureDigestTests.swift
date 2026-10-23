//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import PreviewableGeneratorCore
import Testing

final class SignatureDigestTests {

  var sut: PreviewableSourceGenerator.Type!

  init() {
    sut = PreviewableSourceGenerator.self
  }

  deinit {
    sut = nil
  }

  // MARK: - Overload Names
  @Test
  func overloadNames_readableNamesCollide_preservesCrossPlatformSignatureDigests() throws {
    let source = """
      @PreviewableDouble
      protocol Service {
        func load(_ value: Int) -> Int
        func load(_ value: String) -> Int
        func loadInt() -> Int
      }
      """
    let expected = [
      "  var loadIntSignaturedf5971355a17Stub: Int {",
      "  var loadIntSignature03f99ebfd580Stub: Int {"
    ]

    let generated = try sut.generate(from: [source])
    let result = generated.components(separatedBy: "\n").filter { $0.contains("var loadIntSignature") }

    #expect(result == expected, "Signature digests must remain identical on macOS and Linux.")
  }
}
