//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import PreviewableGeneratorCore
import Testing

struct DoubleAssociatedTypesTests {

  @Test(arguments: [
    "First == Second, Second == Third, Third == String",
    "Third == String, Second == Third, First == Second"
  ])
  func associatedTypes_equalitiesAreTransitive_everyAliasUsesConcreteType(_ conditions: String) throws {
    let source = """
      @PreviewableDouble protocol Service where \(conditions) {
        associatedtype First
        associatedtype Second
        associatedtype Third
      }
      """
    let expected: Set<String> = [
      "typealias First = String",
      "typealias Second = String",
      "typealias Third = String"
    ]

    let generated = try PreviewableSourceGenerator.generate(from: [source])
    let result = Set(
      generated.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.hasPrefix("typealias ") }
    )

    #expect(result == expected, "Transitive equalities must resolve independently of constraint order.")
  }

  @Test
  func associatedTypes_primaryOrderDiffersFromDeclarationOrder_preservesPrimaryOrder() throws {
    let source = """
      @PreviewableDouble protocol Service<Second, First> {
        associatedtype First
        associatedtype Second
      }
      """
    let expected = "final class ServiceDouble<_PreviewableSecond, _PreviewableFirst>: Service"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "Generic parameters must follow the primary associated-type order.")
  }

  @Test
  func associatedTypes_inheritedConstraintUsesLocalAlias_resolvesQualifiedType() throws {
    let source = """
      enum Scope {
        typealias Output = String
        protocol Base where Value == Output { associatedtype Value }
        @PreviewableDouble protocol Service: Base {}
      }
      """
    let expected = "typealias Value = Scope.Output"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "Inherited constraints must retain their declaration's type lookup scope.")
  }

  @Test(arguments: [
    ("@PreviewableDouble protocol Service where String == Value { associatedtype Value }", "typealias Value = String"),
    (
      "@PreviewableDouble protocol Service where Value: Sendable { associatedtype Value }",
      "_PreviewableValue : Sendable"
    ),
    (
      "@PreviewableDouble protocol Service { associatedtype Value; associatedtype _PreviewableValue }",
      "typealias Value = _PreviewableValue_"
    ),
    (
      "protocol Base { associatedtype Value }; protocol Left: Base {}; protocol Right: Base {}; @PreviewableDouble protocol Service: Left, Right {}",
      "typealias Value = _PreviewableValue"
    )
  ])
  func associatedTypes_constraintsAndNamesOverlap_preservesResolvedIdentity(
    _ source: String,
    _ expected: String
  ) throws {
    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(
      result.contains(expected),
      "Associated identities must survive reversed bindings and inherited name collisions."
    )
  }

}
