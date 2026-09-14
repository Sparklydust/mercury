import SwiftSyntax

/// Validates the constraints required by generic response storage.
enum GenericResponseValidator {

  /// Rejects generic response parameters without a known `Sendable` conformance.
  /// - Parameters:
  ///   - function: The method whose return type uses generic parameters.
  ///   - index: Local protocols and aliases used to resolve inherited constraints.
  /// - Throws: `GenerationError` when a response parameter lacks a `Sendable` constraint.
  static func validate(_ function: FunctionDeclSyntax, index: ModuleIndex) throws {
    guard let returnType = function.signature.returnClause?.type else { return }
    let parameters = function.genericParameterClause?.parameters ?? []
    let names = Set(parameters.map(\.name.text))
    var sendable: Set<String> = []
    for parameter in parameters {
      if let constraint = parameter.inheritedType, impliesSendable(constraint, index: index) {
        sendable.insert(parameter.name.text)
      }
    }
    for requirement in function.genericWhereClause?.requirements ?? [] {
      if case .conformanceRequirement(let constraint) = requirement.requirement,
        impliesSendable(constraint.rightType, index: index)
      {
        sendable.insert(constraint.leftType.trimmedDescription)
      }
    }
    if let name = Set(returnType.writtenTypeNames).intersection(names).subtracting(sendable).sorted().first {
      throw GenerationError.message(
        "@PreviewableDouble generic response '\(name)' in '\(function.name.text)' "
          + "requires a Sendable constraint — add '\(name): Sendable'"
      )
    }
  }

  /// Recognizes `Sendable` directly or through local protocol and alias constraints.
  /// - Parameters:
  ///   - type: The constraint type to inspect.
  ///   - index: Local declarations used to resolve the constraint.
  ///   - scope: Enclosing type names for resolving inherited constraints.
  ///   - visited: Declarations already inspected to prevent recursive lookup.
  private static func impliesSendable(
    _ type: TypeSyntax,
    index: ModuleIndex,
    scope: [String] = [],
    visited: Set<String> = []
  ) -> Bool {
    if let composition = type.as(CompositionTypeSyntax.self) {
      return composition.elements.contains {
        impliesSendable($0.type, index: index, scope: scope, visited: visited)
      }
    }
    let name = type.trimmedDescription
    guard let resolved = index.resolve(name, scope: scope) else {
      return ["Sendable", "Swift.Sendable", "_Concurrency.Sendable"].contains(name)
    }
    guard !visited.contains(resolved) else { return false }
    let next = visited.union([resolved])
    let enclosing = resolved.split(separator: ".").dropLast().map(String.init)
    if let alias = index.typeAliases[resolved] {
      return impliesSendable(alias, index: index, scope: enclosing, visited: next)
    }
    guard let declaration = index.protocols[resolved] else { return false }
    return (declaration.inheritanceClause?.inheritedTypes ?? []).contains {
      impliesSendable($0.type, index: index, scope: enclosing, visited: next)
    }
  }
}
