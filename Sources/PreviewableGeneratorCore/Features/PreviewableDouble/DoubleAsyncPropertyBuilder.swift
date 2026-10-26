//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

/// Gives async getters the same response snapshots, error stubs, and spies as async methods.
enum DoubleAsyncPropertyBuilder {

  static func generate(
    context: DoublePropertyContext,
    getter: AccessorDeclSyntax,
    name: String,
    type: TypeSyntax,
    signature: String,
    resolver: inout DefaultValueResolver
  ) throws -> GeneratedProperty {
    let function = function(declaration: context.declaration, getter: getter, name: name, type: type)
    let generated = try PreviewableDoubleMemberBuilder.methodDeclaration(
      from: function,
      access: context.access,
      isolated: context.isolated,
      sendable: context.sendable,
      resolver: &resolver,
      stubName: name,
      recordingKey: name + ".get"
    )
    let accessor = "get \(getter.effectSpecifiers!.trimmedDescription) \(generated.body)"

    return GeneratedProperty(
      stub: generated.stubs.joined(separator: "\n\n"),
      requirement: "\(signature) {\n\(accessor.indented(by: 2))\n}"
    )
  }

  private static func function(
    declaration: VariableDeclSyntax,
    getter: AccessorDeclSyntax,
    name: String,
    type: TypeSyntax
  ) -> FunctionDeclSyntax {
    FunctionDeclSyntax(
      attributes: declaration.attributes,
      modifiers: declaration.modifiers,
      name: .identifier(name),
      signature: FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax(parameters: []),
        effectSpecifiers: FunctionEffectSpecifiersSyntax(
          asyncSpecifier: getter.effectSpecifiers?.asyncSpecifier,
          throwsClause: getter.effectSpecifiers?.throwsClause
        ),
        returnClause: ReturnClauseSyntax(type: type)
      )
    )
  }
}
