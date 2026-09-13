import SwiftSyntax

/// Resolves fake construction once, before defaults or source are generated.
enum FakeDeclarationResolver {

  /// Validates an annotation and resolves its initializer, property types, and factory visibility.
  /// - Parameters:
  ///   - annotation: The fake annotation and its declaration.
  ///   - index: Module declarations used to qualify types and validate access.
  /// - Throws: `GenerationError` when the declaration or its construction contract is unsupported.
  static func resolve(_ annotation: AnnotatedDeclaration, index: ModuleIndex) throws -> ResolvedFake {
    if let extended = annotation.declaration.as(ExtensionDeclSyntax.self) {
      return try PreviewableExternalFakeGenerator.resolve(annotation, in: extended)
    }
    let members: MemberBlockItemListSyntax
    let modifiers: DeclModifierListSyntax
    let genericClause: GenericParameterClauseSyntax?
    let isClass: Bool
    if let declaration = annotation.declaration.as(StructDeclSyntax.self) {
      members = declaration.memberBlock.members
      modifiers = declaration.modifiers
      genericClause = declaration.genericParameterClause
      isClass = false
    } else if let declaration = annotation.declaration.as(ClassDeclSyntax.self) {
      members = declaration.memberBlock.members
      modifiers = declaration.modifiers
      genericClause = declaration.genericParameterClause
      isClass = true
    } else {
      throw GenerationError.message("@PreviewableFake can only be applied to a structure or class")
    }
    guard annotation.attribute.arguments == nil else {
      throw GenerationError.message(
        "@PreviewableFake reads the stored properties of a type declared in this module — remove 'parameters:'"
      )
    }
    guard !modifiers.isFileScoped else {
      throw GenerationError.message(
        "@PreviewableFake cannot access a private or fileprivate type from generated source")
    }
    guard !members.contains(where: { $0.decl.as(FunctionDeclSyntax.self)?.name.text == "fake" }) else {
      throw GenerationError.message("@PreviewableFake conflicts with an existing 'fake' member")
    }
    let generics = Set(genericClause?.parameters.map(\.name.text) ?? [])
    let rewriter = TypeNameResolver(
      index: index, scope: annotation.qualifiedName.split(separator: ".").map(String.init), genericParameters: generics
    )
    let rawProperties = try PreviewableStoredPropertyCollector.storedProperties(in: members)
    let properties = rawProperties.map {
      StoredProperty(name: $0.name, type: rewriter.rewrite($0.type).cast(TypeSyntax.self), isMutable: $0.isMutable)
    }
    if isClass && properties.contains(where: { !$0.isMutable }) {
      throw GenerationError.message("@PreviewableFake classes require mutable fake properties and an accessible init()")
    }
    let initializerThrows = try PreviewableFakeValidator.validateInitializer(
      in: members, of: annotation.qualifiedName, isClass: isClass, properties: rawProperties
    )
    try PreviewableFakeValidator.validateFactoryAccess(
      of: annotation.qualifiedName, access: AccessLevel(modifiers: modifiers), properties: properties, index: index
    )
    let suffix = genericClause.map { "<" + $0.parameters.map(\.name.text).joined(separator: ", ") + ">" } ?? ""
    return ResolvedFake(
      annotation: annotation, typeName: annotation.qualifiedName, returnType: annotation.qualifiedName + suffix,
      access: modifiers.accessPrefix, properties: properties, genericParameters: generics,
      convenienceInitializer: isClass && !properties.isEmpty, initializerThrows: initializerThrows
    )
  }
}
