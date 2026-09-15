//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Collects everything a generated double must witness, including the requirements it inherits.
enum PreviewableRequirementFlattener {

  /// Collects the protocol's own requirements followed by those of every base protocol declared in the module.
  /// - Parameters:
  ///   - declaration: The protocol whose requirements are collected.
  ///   - index: The module declarations used for inheritance and type qualification.
  ///   - visited: Qualified protocol names already traversed; updated to prevent duplicate traversal.
  /// - Throws: `GenerationError` when an inherited non-marker protocol is absent from the module.
  static func requirements(
    of declaration: ProtocolDeclSyntax,
    index: ModuleIndex,
    visited: inout Set<String>
  ) throws -> [MemberBlockItemSyntax] {
    let qualified = index.protocols.first { $0.value.id == declaration.id }?.key ?? declaration.name.text
    guard visited.insert(qualified).inserted else { return [] }
    let scope = qualified.split(separator: ".").map(String.init)
    let associatedNames = associatedNames(in: declaration, index: index)
    let rewriter = TypeNameResolver(index: index, scope: scope, genericParameters: associatedNames)
    var members = declaration.memberBlock.members.map { rewriter.rewrite($0).cast(MemberBlockItemSyntax.self) }

    for inherited in declaration.inheritanceClause?.inheritedTypes ?? [] {
      var type = inherited.type
      while let attributed = type.as(AttributedTypeSyntax.self) { type = attributed.baseType }
      let name = type.trimmedDescription
      let markerName = name.hasPrefix("Swift.") ? String(name.dropFirst("Swift.".count)) : name
      if markerProtocols.contains(markerName) { continue }
      guard let resolved = index.resolve(name, scope: scope), let base = index.protocols[resolved] else {
        throw GenerationError.message(
          """
          @PreviewableDouble cannot read the requirements of '\(name)' \
          — it is not declared in this module
          """
        )
      }
      members.append(
        contentsOf: try requirements(of: base, index: index, visited: &visited)
      )
    }
    return members
  }

  /// Collects only associated names visible through this protocol's local inheritance graph.
  private static func associatedNames(
    in declaration: ProtocolDeclSyntax, index: ModuleIndex, visited: Set<String> = []
  ) -> Set<String> {
    let name = index.protocols.first { $0.value.id == declaration.id }?.key ?? declaration.name.text
    guard !visited.contains(name) else { return [] }
    var names = Set(
      declaration.memberBlock.members.compactMap {
        $0.decl.as(AssociatedTypeDeclSyntax.self)?.name.text
      })
    for inherited in declaration.inheritanceClause?.inheritedTypes ?? [] {
      if let key = index.resolve(inherited.type.trimmedDescription, scope: name.split(separator: ".").map(String.init)),
        let base = index.protocols[key]
      {
        names.formUnion(associatedNames(in: base, index: index, visited: visited.union([name])))
      }
    }
    return names
  }

  /// Protocols that add no requirement of their own, so a double need not read them.
  private static let markerProtocols: Set<String> = [
    "AnyObject", "Sendable", "Any",
  ]
}
