//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

/// Collects associated components that may cross a nonisolated storage boundary.
final class AssociatedSendableCollector: SyntaxVisitor {

  private let parameters: Set<String>
  private(set) var types: Set<String> = []

  /// Creates a collector for the generated generic parameter names.
  /// - Parameter parameters: The double's free associated-type parameters.
  init(parameters: Set<String>) {
    self.parameters = parameters
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
    if !parameters.isDisjoint(with: TypeSyntax(node).writtenTypeNames) {
      types.insert(node.trimmedDescription)
      return .skipChildren
    }
    return .visitChildren
  }

  override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
    if parameters.contains(node.name.text) {
      types.insert(node.name.text)
    }
    return .visitChildren
  }
}
