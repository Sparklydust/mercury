//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

/// Normalizes type spellings for initializer matching without changing emitted declarations.
final class InitializerTypeResolver: SyntaxRewriter {

  private let index: ModuleIndex
  private let scope: [String]
  private let visitedAliases: Set<String>

  private init(
    index: ModuleIndex,
    scope: [String],
    visitedAliases: Set<String> = []
  ) {
    self.index = index
    self.scope = scope
    self.visitedAliases = visitedAliases
  }

  /// Returns a whitespace-independent identity with local aliases and standard module qualifiers resolved.
  /// - Parameters:
  ///   - type: The property or initializer parameter type.
  ///   - index: The module declarations and nongeneric aliases available for lookup.
  ///   - scope: Enclosing type names, from outermost to innermost.
  static func identity(
    of type: TypeSyntax,
    index: ModuleIndex,
    scope: [String]
  ) -> String {
    let resolver = InitializerTypeResolver(index: index, scope: scope)

    return resolver
      .rewrite(type)
      .tokens(viewMode: .sourceAccurate)
      .map(\.text)
      .joined()
      .replacingOccurrences(of: "@escaping", with: "")
  }

  override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
    let rewritten = super.visit(node)
    let name = node.name.text

    if let qualified = index.resolve(name, scope: scope) {
      if node.genericArgumentClause == nil, let alias = expandedAlias(named: qualified) {
        return alias
      }
      let arguments = rewritten.as(IdentifierTypeSyntax.self)?.genericArgumentClause?.trimmedDescription ?? ""
      return TypeSyntax.parsed(from: qualified + arguments) ?? rewritten
    }
    let module: String

    if Self.swiftTypes.contains(name) {
      module = "Swift"
    } else if Self.foundationTypes.contains(name) {
      module = "Foundation"
    } else {
      return rewritten
    }

    return TypeSyntax.parsed(from: module + "." + rewritten.trimmedDescription) ?? rewritten
  }

  override func visit(_ node: MemberTypeSyntax) -> TypeSyntax {
    guard node.genericArgumentClause == nil,
          let qualified = index.resolve(node.trimmedDescription, scope: scope),
          let alias = expandedAlias(named: qualified)
    else { return super.visit(node) }

    return alias
  }

  /// Expands a nongeneric alias in its declaration scope, terminating cyclic lookup.
  /// - Parameter name: The qualified alias name.
  private func expandedAlias(named name: String) -> TypeSyntax? {
    guard !visitedAliases.contains(name), let target = index.typeAliases[name] else { return nil }
    let resolver = InitializerTypeResolver(
      index: index,
      scope: name.split(separator: ".").dropLast().map(String.init),
      visitedAliases: visitedAliases.union([name])
    )
    return resolver.rewrite(target).cast(TypeSyntax.self)
  }

  private static let swiftTypes: Set<String> = [
    "Bool", "String", "Substring", "Character", "Int", "Int8", "Int16", "Int32", "Int64",
    "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Float", "Float16", "Float32", "Float64", "Float80",
    "Double", "Array", "Dictionary", "Set", "Optional", "Result", "Void", "ContiguousArray"
  ]

  private static let foundationTypes: Set<String> = [
    "Date", "UUID", "URL",
    "Data", "Decimal", "TimeInterval"
  ]
}
