//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

/// Resolves fake construction once, before defaults or source are generated.
enum FakeDeclarationResolver {

  /// Validates an annotation and resolves its initializer, property types, and factory visibility.
  /// - Parameters:
  ///   - annotation: The fake annotation and its declaration.
  ///   - index: Module declarations used to qualify types and validate access.
  /// - Throws: `GenerationError` when the declaration or its construction contract is unsupported.
  static func resolve(
    _ annotation: AnnotatedDeclaration,
    index: ModuleIndex
  ) throws -> ResolvedFake {
    if let extended = annotation.declaration.as(ExtensionDeclSyntax.self) {
      return try PreviewableExternalFakeGenerator.resolve(annotation, in: extended)
    }
    let definition = try ownedDefinition(for: annotation)
    try validate(annotation, definition: definition)
    let generics = Set(definition.genericClause?.parameters.map(\.name.text) ?? [])
    let rawProperties = try PreviewableStoredPropertyCollector.storedProperties(in: definition.members)
    let properties = try qualifiedProperties(
      rawProperties,
      annotation: annotation,
      definition: definition,
      generics: generics,
      index: index
    )
    let initializerThrows = try validateConstruction(
      annotation: annotation,
      definition: definition,
      rawProperties: rawProperties,
      properties: properties,
      index: index
    )
    return resolvedRecipe(
      annotation: annotation,
      definition: definition,
      properties: properties,
      initializerThrows: initializerThrows,
      index: index
    )
  }

  private static func resolvedRecipe(
    annotation: AnnotatedDeclaration,
    definition: OwnedFakeDefinition,
    properties: [StoredProperty],
    initializerThrows: Bool,
    index: ModuleIndex
  ) -> ResolvedFake {

    let suffix = definition
      .genericClause
      .map { "<" + $0.parameters.map(\.name.text).joined(separator: ", ") + ">" } ?? ""

    return ResolvedFake(
      annotation: annotation,
      typeName: annotation.qualifiedName,
      returnType: annotation.qualifiedName + suffix,
      access: index.accessPrefix(for: annotation.qualifiedName),
      properties: properties,
      genericParameters: Set(definition.genericClause?.parameters.map(\.name.text) ?? []),
      convenienceInitializer: definition.isClass && !properties.isEmpty,
      initializerThrows: initializerThrows
    )
  }

  private static func ownedDefinition(
    for annotation: AnnotatedDeclaration
  ) throws -> OwnedFakeDefinition {

    if let declaration = annotation.declaration.as(StructDeclSyntax.self) {
      return OwnedFakeDefinition(
        members: declaration.memberBlock.members,
        modifiers: declaration.modifiers,
        genericClause: declaration.genericParameterClause,
        isClass: false
      )
    }

    if let declaration = annotation.declaration.as(ClassDeclSyntax.self) {
      return OwnedFakeDefinition(
        members: declaration.memberBlock.members,
        modifiers: declaration.modifiers,
        genericClause: declaration.genericParameterClause,
        isClass: true
      )
    }
    throw GenerationError.message("@PreviewableFake can only be applied to a structure or class")
  }

  private static func validate(
    _ annotation: AnnotatedDeclaration,
    definition: OwnedFakeDefinition
  ) throws {
    let hasArguments = if case .argumentList(let arguments) = annotation.attribute.arguments {
      !arguments.isEmpty
    } else {
      annotation.attribute.arguments != nil
    }

    guard !hasArguments else {
      throw GenerationError.message(
        "@PreviewableFake reads the stored properties of a type declared in this module — remove 'parameters:'"
      )
    }
    guard !definition.modifiers.isFileScoped else {
      throw GenerationError.message(
        "@PreviewableFake cannot access a private or fileprivate type from generated source"
      )
    }
    guard !definition.members.contains(where: { $0.decl.as(FunctionDeclSyntax.self)?.name.text == "fake" }) else {
      throw GenerationError.message("@PreviewableFake conflicts with an existing 'fake' member")
    }
  }

  private static func qualifiedProperties(
    _ rawProperties: [StoredProperty],
    annotation: AnnotatedDeclaration,
    definition: OwnedFakeDefinition,
    generics: Set<String>,
    index: ModuleIndex
  ) throws -> [StoredProperty] {
    let rewriter = TypeNameResolver(
      index: index,
      scope: annotation.qualifiedName.split(separator: ".").map(String.init),
      genericParameters: generics
    )
    let properties = rawProperties.map {
      StoredProperty(name: $0.name, type: rewriter.rewrite($0.type).cast(TypeSyntax.self), isMutable: $0.isMutable)
    }
    if definition.isClass && properties.contains(where: { !$0.isMutable }) {
      throw GenerationError.message("@PreviewableFake classes require mutable fake properties and an accessible init()")
    }
    return properties
  }

  private static func validateConstruction(
    annotation: AnnotatedDeclaration,
    definition: OwnedFakeDefinition,
    rawProperties: [StoredProperty],
    properties: [StoredProperty],
    index: ModuleIndex
  ) throws -> Bool {
    let initializerThrows = try PreviewableFakeValidator.validateInitializer(
      in: definition.members,
      of: annotation.qualifiedName,
      isClass: definition.isClass,
      properties: rawProperties,
      index: index,
      inheritance: annotation.declaration.as(ClassDeclSyntax.self)?.inheritanceClause
    )
    try PreviewableFakeValidator.validateFactoryAccess(
      of: annotation.qualifiedName,
      access: index.typeAccess[annotation.qualifiedName] ?? .internal,
      properties: properties,
      index: index
    )
    return initializerThrows
  }
}
