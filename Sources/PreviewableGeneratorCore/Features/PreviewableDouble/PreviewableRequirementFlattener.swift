//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

/// Collects everything a generated double must witness, including the requirements it inherits.
enum PreviewableRequirementFlattener {

  /// Collects the protocol's own requirements followed by those of every base protocol declared in the module.
  /// - Parameters:
  ///   - declaration: The protocol whose requirements are collected.
  ///   - index: The module declarations used for inheritance and type qualification.
  ///   - visited: Qualified protocol names already traversed; updated to prevent duplicate traversal.
  /// - Throws: `GenerationError` for conditional declarations or requirements, or an unreadable inherited protocol.
  static func requirements(
    of declaration: ProtocolDeclSyntax,
    index: ModuleIndex,
    visited: inout Set<String>
  ) throws -> [MemberBlockItemSyntax] {
    let qualified = index.protocols.first { $0.value.id == declaration.id }?.key ?? declaration.name.text

    guard visited.insert(qualified).inserted else { return [] }
    try validateDeclarationScope(declaration, qualifiedName: qualified)
    guard !declaration.memberBlock.members.contains(where: { $0.decl.is(IfConfigDeclSyntax.self) }) else {
      throw GenerationError.message(
        "@PreviewableDouble does not support conditional requirements in '\(qualified)' — declare requirements without #if"
      )
    }
    let scope = qualified.split(separator: ".").map(String.init)
    let associatedNames = associatedNames(in: declaration, index: index)
    let rewriter = TypeNameResolver(index: index, scope: scope, genericParameters: associatedNames)
    var members = declaration.memberBlock.members.map { rewriter.rewrite($0).cast(MemberBlockItemSyntax.self) }

    for inherited in declaration.inheritanceClause?.inheritedTypes ?? [] {
      var type = inherited.type

      while let attributed = type.as(AttributedTypeSyntax.self) {
        type = attributed.baseType
      }
      let name = type.trimmedDescription
      let markerName = name.hasPrefix("Swift.") ? String(name.dropFirst("Swift.".count)) : name

      guard !markerProtocols.contains(markerName) else { continue }
      guard let resolved = index.resolve(name, scope: scope), let base = index.protocols[resolved] else {
        throw GenerationError.message(
          """
          @PreviewableDouble cannot read the requirements of '\(name)' \
          — it is not declared in this module
          """
        )
      }

      members.append(contentsOf: try requirements(of: base, index: index, visited: &visited))
    }

    return members
  }

  /// Rejects conditional base declarations because indexing cannot select the consumer's active branch.
  private static func validateDeclarationScope(
    _ declaration: ProtocolDeclSyntax,
    qualifiedName: String
  ) throws {
    var ancestor = declaration.parent

    while let parent = ancestor {
      if parent.is(IfConfigDeclSyntax.self) {
        throw GenerationError.message(
          "@PreviewableDouble does not support conditional declaration of '\(qualifiedName)' — declare it without #if"
        )
      }
      ancestor = parent.parent
    }
  }

  /// Collects only associated names visible through this protocol's local inheritance graph.
  private static func associatedNames(
    in declaration: ProtocolDeclSyntax,
    index: ModuleIndex,
    visited: Set<String> = []
  ) -> Set<String> {
    let name = index.protocols.first { $0.value.id == declaration.id }?.key ?? declaration.name.text

    guard !visited.contains(name) else { return [] }
    var names = Set(
      declaration.memberBlock.members.compactMap {
        $0.decl.as(AssociatedTypeDeclSyntax.self)?.name.text
      }
    )

    for inherited in declaration.inheritanceClause?.inheritedTypes ?? [] {
      guard let key = index.resolve(inherited.type.trimmedDescription, scope: name.split(separator: ".").map(String.init)),
            let base = index.protocols[key]
      else { continue }

      names.formUnion(associatedNames(in: base, index: index, visited: visited.union([name])))
    }

    return names
  }

  /// Protocols that add no requirement of their own, so a double need not read them.
  private static let markerProtocols: Set<String> = [
    "AnyObject", "Sendable", "Any"
  ]
}
