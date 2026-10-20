//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Exposes the syntax shared by callable and property requirement identity generation.
struct DoubleRequirementSyntax {

  let member: MemberBlockItemSyntax
  let subscriptDeclaration: SubscriptDeclSyntax?
  let function: FunctionDeclSyntax?

  var variable: VariableDeclSyntax? { member.decl.as(VariableDeclSyntax.self) }
  private var initializer: InitializerDeclSyntax? { member.decl.as(InitializerDeclSyntax.self) }
  var modifiers: DeclModifierListSyntax { function?.modifiers ?? variable?.modifiers ?? initializer?.modifiers ?? [] }
  var attributes: AttributeListSyntax { function?.attributes ?? variable?.attributes ?? initializer?.attributes ?? [] }
  var name: String {
    subscriptDeclaration != nil
      ? "subscript"
      : function?.name.text
        ?? variable?.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text ?? "init"
  }

  init(_ member: MemberBlockItemSyntax) {
    self.member = member
    subscriptDeclaration = member.decl.as(SubscriptDeclSyntax.self)
    function = member.decl.as(FunctionDeclSyntax.self) ?? subscriptDeclaration.map(DoubleRequirement.getterFunction)
  }
}
