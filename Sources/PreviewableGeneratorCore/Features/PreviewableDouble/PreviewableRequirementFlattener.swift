//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Collects everything a generated double must witness, including the requirements it inherits.
enum PreviewableRequirementFlattener {

  /// Collects the protocol's own requirements followed by those of every base protocol declared in the module.
  static func requirements(
    of declaration: ProtocolDeclSyntax,
    index: ModuleIndex,
    visited: inout Set<String>
  ) throws -> [MemberBlockItemSyntax] {
    let qualified = index.protocols.first { $0.value.id == declaration.id }?.key ?? declaration.name.text
    guard visited.insert(qualified).inserted else { return [] }
    let scope = qualified.split(separator: ".").map(String.init)
    let rewriter = TypeNameResolver(index: index, scope: scope)
    var members = declaration.memberBlock.members.map { rewriter.rewrite($0).cast(MemberBlockItemSyntax.self) }

    for inherited in declaration.inheritanceClause?.inheritedTypes ?? [] {
      let name = inherited.type.trimmedDescription
      if markerProtocols.contains(name) { continue }
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

  /// Protocols that add no requirement of their own, so a double need not read them.
  private static let markerProtocols: Set<String> = [
    "AnyObject", "Sendable", "Any",
  ]
}
