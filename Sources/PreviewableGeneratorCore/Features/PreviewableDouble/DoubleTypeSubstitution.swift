//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

/// Substitutes associated-type references without rewriting requirement names or method-local generic parameters.
final class DoubleTypeSubstitution: SyntaxRewriter {

  private var bindings: [String: String]

  /// Creates a rewriter for resolved associated-type bindings.
  /// - Parameter bindings: Associated names mapped to generic parameters or concrete types.
  init(_ bindings: [String: String]) {
    self.bindings = bindings
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
    guard let replacement = bindings[node.name.text], let type = TypeSyntax.parsed(from: replacement)
    else { return super.visit(node) }

    return type.with(\.leadingTrivia, node.leadingTrivia).with(\.trailingTrivia, node.trailingTrivia)
  }

  override func visit(_ node: MemberTypeSyntax) -> TypeSyntax {
    guard node.baseType.trimmedDescription == "Self", let replacement = bindings[node.name.text],
          let type = TypeSyntax.parsed(from: replacement)
    else { return super.visit(node) }

    return type.with(\.leadingTrivia, node.leadingTrivia).with(\.trailingTrivia, node.trailingTrivia)
  }

  override func visit(_ node: FunctionDeclSyntax) -> DeclSyntax {
    withShadowedBindings(node.genericParameterClause) { super.visit(node) }
  }

  override func visit(_ node: SubscriptDeclSyntax) -> DeclSyntax {
    withShadowedBindings(node.genericParameterClause) { super.visit(node) }
  }

  /// Restores enclosing associated bindings after rewriting a method-local generic scope.
  private func withShadowedBindings(
    _ parameters: GenericParameterClauseSyntax?,
    rewrite: () -> DeclSyntax
  ) -> DeclSyntax {
    let previous = bindings

    for parameter in parameters?.parameters ?? [] {
      bindings.removeValue(forKey: parameter.name.text)
    }
    defer { bindings = previous }
    return rewrite()
  }
}
