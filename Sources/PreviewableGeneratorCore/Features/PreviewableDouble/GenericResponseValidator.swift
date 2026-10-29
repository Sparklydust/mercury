//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import SwiftSyntax

/// Validates the constraints required by generic response storage.
enum GenericResponseValidator {

  /// Rejects generic response parameters without a known `Sendable` conformance.
  /// - Parameters:
  ///   - function: The method whose return type uses generic parameters.
  ///   - index: Local protocols and aliases used to resolve inherited constraints.
  /// - Throws: `GenerationError` when a response parameter lacks a `Sendable` constraint.
  static func validate(
    _ function: FunctionDeclSyntax,
    index: ModuleIndex
  ) throws {
    guard let returnType = function.signature.returnClause?.type else { return }

    let parameters = function.genericParameterClause?.parameters ?? []
    let names = Set(parameters.map(\.name.text))
    var sendable: Set<String> = []

    for parameter in parameters {
      guard let constraint = parameter.inheritedType,
            impliesSendable(constraint, index: index)
      else { continue }
      sendable.insert(parameter.name.text)
    }

    for requirement in function.genericWhereClause?.requirements ?? [] {
      guard case .conformanceRequirement(let constraint) = requirement.requirement,
            impliesSendable(constraint.rightType, index: index)
      else { continue }
      sendable.insert(constraint.leftType.trimmedDescription)
    }
    try validate(returnType, parameters: names, sendable: sendable, method: function.name.text, index: index)
  }

  /// Checks generic components of a response, including associated types and closure sendability.
  /// - Parameters:
  ///   - type: The response type or one of its components.
  ///   - parameters: The method's generic parameter names.
  ///   - sendable: Generic and associated types with known `Sendable` constraints.
  ///   - method: The method name included in diagnostics.
  ///   - index: Local declarations used to recognize globally isolated closure types.
  /// - Throws: `GenerationError` when a component needs an additional constraint or attribute.
  private static func validate(
    _ type: TypeSyntax,
    parameters: Set<String>,
    sendable: Set<String>,
    method: String,
    index: ModuleIndex
  ) throws {
    if let attributed = type.as(AttributedTypeSyntax.self), attributed.baseType.is(FunctionTypeSyntax.self),
      (attributed.attributes.contains(where: {
        guard case .attribute(let attribute) = $0 else { return false }
        return ["Sendable", "Swift.Sendable"].contains(attribute.attributeName.trimmedDescription)
      }) || !DoubleStorageBuilder.isolationAttributes(in: attributed.attributes, index: index).isEmpty) {
      return
    }

    if type.is(FunctionTypeSyntax.self) {
      throw GenerationError.message("@PreviewableDouble closure response in '\(method)' requires @Sendable")
    }
    let name = type.trimmedDescription

    if parameters.contains(name)
      || (type.is(MemberTypeSyntax.self) && parameters.contains(name.components(separatedBy: ".")[0])) {
      guard !sendable.contains(name) else { return }
      throw GenerationError.message(
        "@PreviewableDouble generic response '\(name)' in '\(method)' "
          + "requires a Sendable constraint — add '\(name): Sendable'"
      )
    }
    for child in Syntax(type).children(viewMode: .sourceAccurate) {
      try validateComponents(in: child, parameters: parameters, sendable: sendable, method: method, index: index)
    }
  }

  /// Traverses wrapper syntax until a nested response type can be validated.
  /// - Parameters:
  ///   - syntax: A type's child syntax, such as a tuple element or generic argument list.
  ///   - parameters: The method's generic parameter names.
  ///   - sendable: Generic and associated types with known `Sendable` constraints.
  ///   - method: The method name included in diagnostics.
  ///   - index: Local declarations used to recognize globally isolated closure types.
  /// - Throws: `GenerationError` for an unsupported nested response component.
  private static func validateComponents(
    in syntax: Syntax,
    parameters: Set<String>,
    sendable: Set<String>,
    method: String,
    index: ModuleIndex
  ) throws {
    guard let type = syntax.as(TypeSyntax.self) else {
      for child in syntax.children(viewMode: .sourceAccurate) {
        try validateComponents(in: child, parameters: parameters, sendable: sendable, method: method, index: index)
      }
      return
    }
    try validate(type, parameters: parameters, sendable: sendable, method: method, index: index)
  }

  /// Recognizes `Sendable` directly or through local protocol and alias constraints.
  /// - Parameters:
  ///   - type: The constraint type to inspect.
  ///   - index: Local declarations used to resolve the constraint.
  ///   - scope: Enclosing type names for resolving inherited constraints.
  ///   - visited: Declarations already inspected to prevent recursive lookup.
  static func impliesSendable(
    _ type: TypeSyntax,
    index: ModuleIndex,
    scope: [String] = [],
    visited: Set<String> = []
  ) -> Bool {
    if let attributed = type.as(AttributedTypeSyntax.self) {
      return impliesSendable(attributed.baseType, index: index, scope: scope, visited: visited)
    }
    if let composition = type.as(CompositionTypeSyntax.self) {
      return composition.elements.contains {
        impliesSendable($0.type, index: index, scope: scope, visited: visited)
      }
    }
    let name = type.trimmedDescription

    guard let resolved = index.resolve(name, scope: scope)
    else { return ["Sendable", "Swift.Sendable", "_Concurrency.Sendable"].contains(name) }

    guard !visited.contains(resolved) else { return false }

    let next = visited.union([resolved])
    let enclosing = resolved.split(separator: ".").dropLast().map(String.init)

    if let alias = index.typeAliases[resolved] {
      return impliesSendable(alias, index: index, scope: enclosing, visited: next)
    }
    guard let declaration = index.protocols[resolved] else { return false }

    let inherited = (declaration.inheritanceClause?.inheritedTypes ?? []).contains {
      impliesSendable($0.type, index: index, scope: enclosing, visited: next)
    }

    return inherited || (declaration.genericWhereClause?.requirements ?? []).contains {
      guard case .conformanceRequirement(let constraint) = $0.requirement,
            constraint.leftType.trimmedDescription == "Self"
      else { return false }

      return impliesSendable(constraint.rightType, index: index, scope: enclosing, visited: next)
    }
  }
}
