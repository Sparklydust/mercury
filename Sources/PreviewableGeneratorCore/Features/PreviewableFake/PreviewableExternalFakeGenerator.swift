//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

/// Generates the fake factory for a type declared outside this module, whose properties the annotation lists.
enum PreviewableExternalFakeGenerator {

  /// Resolves external construction from the parameter labels, types, and throwing flag in the annotation.
  ///
  /// The external initializer signature is checked when generated source is compiled.
  /// - Parameters:
  ///   - annotation: The attribute containing the explicit initializer contract.
  ///   - declaration: The extension receiving the generated factory.
  /// - Throws: `GenerationError` for unsupported extensions or malformed construction arguments.
  static func resolve(
    _ annotation: AnnotatedDeclaration,
    in declaration: ExtensionDeclSyntax
  ) throws -> ResolvedFake {
    let typeName = annotation.name

    guard declaration.genericWhereClause == nil else {
      throw GenerationError.message(
        """
        @PreviewableFake cannot generate for the constrained extension of '\(typeName)' \
        — remove the 'where' clause
        """
      )
    }
    guard !typeName.contains("<") else {
      throw GenerationError.message(
        """
        @PreviewableFake cannot generate for the generic type '\(typeName)' \
        — extend an unspecialised type
        """
      )
    }
    var initializerThrows = false

    if case .argumentList(let arguments)? = annotation.attribute.arguments,
       let flag = arguments.first(where: { $0.label?.text == "throwing" }) {
      guard let literal = flag.expression.as(BooleanLiteralExprSyntax.self) else {
        throw GenerationError.message("@PreviewableFake 'throwing' must be a Boolean literal")
      }
      initializerThrows = literal.literal.text == "true"
    }

    return ResolvedFake(
      annotation: annotation,
      typeName: typeName,
      returnType: typeName,
      access: declaration.modifiers.accessPrefix,
      properties: try declaredParameters(of: annotation),
      genericParameters: [],
      convenienceInitializer: false,
      initializerThrows: initializerThrows
    )
  }

  /// Returns the initializer parameters declared in the attribute for a type the generator cannot read.
  /// - Throws: `GenerationError` when `parameters:` is missing, malformed, empty or repeats a name.
  private static func declaredParameters(of annotation: AnnotatedDeclaration) throws -> [StoredProperty] {
    guard case .argumentList(let arguments)? = annotation.attribute.arguments,
          let list = arguments.first(where: { $0.label?.text == "parameters" }),
          let elements = list.expression.as(ArrayExprSyntax.self)?.elements
    else {
      throw GenerationError.message(
        """
        @PreviewableFake cannot read '\(annotation.name)', declared outside this module \
        — declare its initializer parameters in 'parameters:'
        """
      )
    }

    var properties: [StoredProperty] = []

    for element in elements {
      guard let parameter = declaredParameter(from: element.expression) else {
        throw GenerationError.message(
          """
          @PreviewableFake expects every parameter of '\(annotation.name)' to read as \
          ('name', Type.self)
          """
        )
      }
      properties.append(parameter)
    }

    guard !properties.isEmpty else {
      throw GenerationError.message(
        """
        @PreviewableFake requires at least one parameter for '\(annotation.name)' \
        — list the values its initializer takes
        """
      )
    }
    guard Set(properties.map(\.name)).count == properties.count else {
      throw GenerationError.message(
        "@PreviewableFake requires distinct parameter names for '\(annotation.name)'"
      )
    }

    return properties
  }

  /// Reads one `("name", Type.self)` pair, or returns `nil` when the pair is not spelled that way.
  private static func declaredParameter(from expression: ExprSyntax) -> StoredProperty? {
    guard let pair = expression.as(TupleExprSyntax.self), pair.elements.count == 2,
          let literal = pair.elements.first?.expression.as(StringLiteralExprSyntax.self),
          let name = literal.representedLiteralValue, name.isIdentifier,
          let metatype = pair.elements.last?.expression.as(MemberAccessExprSyntax.self),
          metatype.declName.baseName.tokenKind == .keyword(.self),
          let base = metatype.base,
          let type = TypeSyntax.parsed(from: base.trimmedDescription)
    else { return .none }

    return StoredProperty(name: name, type: type, isMutable: true)
  }
}
