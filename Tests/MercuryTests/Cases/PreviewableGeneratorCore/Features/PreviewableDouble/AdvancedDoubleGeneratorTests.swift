//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import PreviewableGeneratorCore
import Testing

struct AdvancedDoubleGeneratorTests {

  @Test(arguments: [
    ("(_ value: Int)", "(_ renamed: Swift.Int)"),
    ("(_ value: Identifier)", "(_ value: Int)"),
    ("(_ value: Scope.Identifier)", "(_ value: Swift.Int)"),
    ("(_ value: [Int?])", "(_ value: Swift.Array<Swift.Optional<Swift.Int>>)"),
    ("<Value: Codable & Sendable>(_ value: Value)", "<Other>(_ value: Other) where Other: Sendable & Codable"),
    (
      "<A: Collection, B: Sendable>(_ a: A, _ b: B) where A.Element == B",
      "<X: Collection, Y: Sendable>(_ a: X, _ b: Y) where Y == X.Element"
    )
  ])
  func signatures_equivalentSpellings_emitOneWitness(_ first: String, _ second: String) throws {
    let source = """
      typealias Identifier = Scope.Identifier
      enum Scope { typealias Identifier = Swift.Int }
      protocol Base { func load\(first) }
      @PreviewableDouble protocol Service: Base { func load\(second) }
      """
    let expected = 1

    let generated = try PreviewableSourceGenerator.generate(from: [source])
    let result = generated.components(separatedBy: "func load").count - 1

    #expect(result == expected, "Equivalent inherited signatures must produce exactly one witness.")
  }

  @Test
  func signatures_localTypeShadowsStandardType_preservesBothOverloads() throws {
    let source = """
      enum Scope {
        struct Int: Sendable {}
        @PreviewableDouble protocol Service {
          func load(_ value: Int) -> String
          func load(_ value: Swift.Int) -> String
        }
      }
      """
    let expected = 2

    let generated = try PreviewableSourceGenerator.generate(from: [source])
    let result = generated.components(separatedBy: "func load").count - 1

    #expect(result == expected, "A locally declared Int must remain distinct from Swift.Int.")
  }

  @Test
  func overloadNames_declarationsAreReordered_remainStable() throws {
    let members = [
      "func load<Value: Encodable & Sendable>(_ value: Value) -> Int",
      "func load<Other: Decodable & Sendable>(_ value: Other) -> Int",
      "func load(_ value: Int) -> String",
      "func load(_ value: Int) -> Int"
    ]

    let results = try [members, Array(members.reversed())].map { ordered in
      let generated = try PreviewableSourceGenerator.generate(from: [
        "@PreviewableDouble protocol Service { " + ordered.joined(separator: "; ") + " }"
      ])
      return Set(generated.split(separator: "\n").filter { $0.contains("var load") }.map(String.init))
    }

    #expect(results[0] == results[1], "Readable and fallback signature names must ignore declaration order.")
  }

  @Test
  func overloadNames_matchAnotherMethod_remainDistinct() throws {
    let source = """
      @PreviewableDouble protocol Service {
        func load(_ value: Int) -> Int
        func load(_ value: String) -> Int
        func loadInt() -> Int
      }
      """
    let expected = 3

    let generated = try PreviewableSourceGenerator.generate(from: [source])
    let names = generated.split(separator: "\n").filter { $0.contains("var load") }.map(String.init)
    let result = Set(names).count

    #expect(result == expected, "A method named like another overload's stub must get independent storage.")
  }

  @Test
  func properties_inheritedGetterAndSetter_emitWritableWitness() throws {
    let source = """
      protocol Base { var value: Swift.Int { get set } }
      @PreviewableDouble protocol Service: Base { var value: Int { get } }
      """

    let generated = try PreviewableSourceGenerator.generate(from: [source])
    let result = generated.contains("set { valueStub = newValue }")

    #expect(result, "The combined property must satisfy the writable inherited requirement.")
  }

  @Test
  func associatedTypes_unrelatedProtocolUsesSameName_preservesLocalTypeQualification() throws {
    let source = """
      protocol Unrelated { associatedtype Payload }
      enum Scope {
        struct Payload: Sendable {}
        @PreviewableDouble protocol Service { func store(_ value: Payload) }
      }
      """

    let generated = try PreviewableSourceGenerator.generate(from: [source])
    let result = generated.contains("func store(_ value: Scope.Payload)")

    #expect(result, "Unrelated associated declarations must not shadow a local concrete type.")
  }
}
