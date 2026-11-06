//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

/// Resolves known aliases and equivalent type syntax before comparing protocol requirements.
final class DoubleTypeCanonicalizer: SyntaxRewriter {

  private let index: ModuleIndex
  private let scope: [String]
  private let substitutions: [String: String]
  private let visited: Set<String>
  private var failure: GenerationError?

  /// Creates a canonicalizer that respects lexical scope and declaration-local generic names.
  /// - Parameters:
  ///   - index: Locally available declarations and aliases.
  ///   - scope: The enclosing declaration names.
  ///   - substitutions: Generic parameter names mapped to stable positional names.
  ///   - visited: Aliases already being expanded, used to reject cycles.
  init(
    index: ModuleIndex,
    scope: [String],
    substitutions: [String: String] = [:],
    visited: Set<String> = []
  ) {
    self.index = index
    self.scope = scope
    self.substitutions = substitutions
    self.visited = visited
    super.init(viewMode: .sourceAccurate)
  }

  /// Returns a trivia-independent type identity, expanding only declarations available in this module.
  /// - Parameter type: The type to compare.
  /// - Throws: When a local type alias is cyclic.
  func canonical(_ type: TypeSyntax) throws -> String {
    try resolved(type).tokens(viewMode: .sourceAccurate).map(\.text).joined()
  }

  /// Expands known aliases while retaining valid Swift syntax for default construction.
  /// - Parameter type: The type whose aliases and standard-library spellings are resolved.
  /// - Throws: When a local type alias is cyclic.
  func resolved(_ type: TypeSyntax) throws -> TypeSyntax {
    let result = rewrite(type).cast(TypeSyntax.self)
    guard let failure else { return result }
    throw failure
  }

  /// Rewrites an identifier while preserving generic shadowing and external type identities.
  override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
    let rewritten = super.visit(node)
    let name = node.name.text

    if let replacement = substitutions[name] {
      return parsed(replacement, fallback: rewritten)
    }
    if let resolved = index.resolve(name, scope: scope) {
      if let alias = index.typeAliases[resolved], node.genericArgumentClause == nil {
        return expand(alias, named: resolved, fallback: rewritten)
      }
      let arguments = rewritten.as(IdentifierTypeSyntax.self)?.genericArgumentClause?.trimmedDescription ?? ""
      return parsed(resolved + arguments, fallback: rewritten)
    }
    if Self.standardTypes.contains(name) {
      return parsed("Swift." + rewritten.trimmedDescription, fallback: rewritten)
    }

    return rewritten
  }

  /// Expands qualified local aliases without guessing the contents of imported modules.
  override func visit(_ node: MemberTypeSyntax) -> TypeSyntax {
    let name = node.trimmedDescription

    if let replacement = substitutions[name] {
      return parsed(replacement, fallback: TypeSyntax(node))
    }
    if let resolved = index.resolve(name, scope: scope), let alias = index.typeAliases[resolved] {
      return expand(alias, named: resolved, fallback: TypeSyntax(node))
    }
    // A module qualifier is not an independently resolvable type name.
    guard node.baseType.trimmedDescription == "Swift", index.resolve("Swift", scope: scope) == nil
    else { return super.visit(node) }

    var result = node

    if let arguments = node.genericArgumentClause {
      result.genericArgumentClause = rewrite(arguments).cast(GenericArgumentClauseSyntax.self)
    }

    return TypeSyntax(result)
  }

  /// Normalizes array sugar to its standard-library nominal type.
  override func visit(_ node: ArrayTypeSyntax) -> TypeSyntax {
    parsed("Swift.Array<\(rewrite(node.element).trimmedDescription)>", fallback: TypeSyntax(node))
  }

  /// Normalizes dictionary sugar to its standard-library nominal type.
  override func visit(_ node: DictionaryTypeSyntax) -> TypeSyntax {
    parsed(
      "Swift.Dictionary<\(rewrite(node.key).trimmedDescription), \(rewrite(node.value).trimmedDescription)>",
      fallback: TypeSyntax(node)
    )
  }

  /// Normalizes optional sugar while retaining its wrapped type.
  override func visit(_ node: OptionalTypeSyntax) -> TypeSyntax {
    parsed("Swift.Optional<\(rewrite(node.wrappedType).trimmedDescription)>", fallback: TypeSyntax(node))
  }

  /// Normalizes empty and parenthesized tuple types.
  override func visit(_ node: TupleTypeSyntax) -> TypeSyntax {
    if node.elements.isEmpty {
      return parsed("Swift.Void", fallback: TypeSyntax(node))
    }
    if node.elements.count == 1, let element = node.elements.first, element.firstName == nil {
      return rewrite(element.type).cast(TypeSyntax.self)
    }

    return super.visit(node)
  }

  /// Makes protocol composition order irrelevant to identity.
  override func visit(_ node: CompositionTypeSyntax) -> TypeSyntax {
    let elements = node.elements.map { rewrite($0.type).trimmedDescription }.sorted()
    return parsed(elements.joined(separator: " & "), fallback: TypeSyntax(node))
  }

  /// Expands an alias using the scope where the alias was declared.
  private func expand(
    _ alias: TypeSyntax,
    named name: String,
    fallback: TypeSyntax
  ) -> TypeSyntax {
    guard !visited.contains(name) else {
      failure = .message("encountered cyclic type alias '\(name)'")
      return fallback
    }
    let resolver = DoubleTypeCanonicalizer(
      index: index,
      scope: name.split(separator: ".").dropLast().map(String.init),
      visited: visited.union([name])
    )
    do { return try resolver.resolved(alias) } catch let error as GenerationError {
      failure = error
    } catch { failure = .message(String(describing: error)) }
    return fallback
  }

  /// Parses a canonical spelling whose syntax is derived from already parsed types.
  private func parsed(
    _ text: String,
    fallback: TypeSyntax
  ) -> TypeSyntax {
    TypeSyntax.parsed(from: text) ?? fallback
  }

  private static let standardTypes: Set<String> = [
    "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
    "Bool", "String", "Substring", "Character", "Float", "Double", "Void", "Never",
    "Array", "Dictionary", "Set", "Optional", "Result", "AnyObject", "Sendable", "Error",
    "Hashable", "Equatable", "Codable", "Encodable", "Decodable", "Sequence", "Collection",
    "BidirectionalCollection", "RandomAccessCollection", "MutableCollection", "RangeReplaceableCollection",
    "IteratorProtocol", "Comparable", "Identifiable", "RawRepresentable", "CaseIterable"
  ]
}
