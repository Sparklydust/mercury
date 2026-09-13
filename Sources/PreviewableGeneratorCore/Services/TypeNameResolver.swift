import SwiftSyntax

/// Qualifies local type references before declarations move into a generated file.
final class TypeNameResolver: SyntaxRewriter {
  private let index: ModuleIndex
  private let scope: [String]
  private let genericParameters: Set<String>

  init(index: ModuleIndex, scope: [String], genericParameters: Set<String> = []) {
    self.index = index
    self.scope = scope
    self.genericParameters = genericParameters
  }

  override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
    let rewritten = super.visit(node)
    let name = node.name.text
    guard !genericParameters.contains(name),
      let qualified = index.resolve(name, scope: scope), qualified != name,
      let identifier = rewritten.as(IdentifierTypeSyntax.self),
      let result = TypeSyntax.parsed(from: qualified + (identifier.genericArgumentClause?.trimmedDescription ?? ""))
    else { return rewritten }
    return result.with(\.leadingTrivia, node.leadingTrivia).with(\.trailingTrivia, node.trailingTrivia)
  }

  override func visit(_ node: FunctionDeclSyntax) -> DeclSyntax {
    let local = TypeNameResolver(
      index: index, scope: scope,
      genericParameters: genericParameters.union(node.genericParameterClause?.parameters.map(\.name.text) ?? [])
    )
    var result = node
    if let generics = node.genericParameterClause {
      result.genericParameterClause = local.rewrite(generics).cast(GenericParameterClauseSyntax.self)
    }
    result.signature = local.rewrite(node.signature).cast(FunctionSignatureSyntax.self)
    if let constraints = node.genericWhereClause {
      result.genericWhereClause = local.rewrite(constraints).cast(GenericWhereClauseSyntax.self)
    }
    return DeclSyntax(result)
  }
}
