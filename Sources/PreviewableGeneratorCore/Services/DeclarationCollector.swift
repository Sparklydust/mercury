//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Collects every declaration the generator needs, at any nesting depth.
///
/// Traversal includes nested declarations and records unsupported annotation locations for later validation.
final class DeclarationCollector: SyntaxVisitor {

  /// The declarations and annotations collected from the input file.
  private(set) var index = ModuleIndex()
  private let fileIndex: Int

  /// Creates a collector that associates annotations with one input file.
  /// - Parameter fileIndex: The file's zero-based position in the generation input.
  init(fileIndex: Int) {
    self.fileIndex = fileIndex
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
    let position = Self.lexicalPosition(of: node)
    let name = node.name.text
    register(protocol: node, named: name, at: position)
    if let annotated = Self.annotation(in: node.attributes) {
      record(annotated, declaration: DeclSyntax(node), name: name, position: position, node: node)
    }
    return .visitChildren
  }

  override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
    guard let annotated = Self.annotation(in: node.attributes) else { return .visitChildren }
    // The generator never sees the extended type, so its spelling in the extension is the only name there is.
    let name = node.extendedType.trimmedDescription
    if annotated.annotation == .fake { index.fakeAnnotatedTypes.insert(name) }
    record(
      annotated,
      declaration: DeclSyntax(node),
      name: name,
      position: Self.lexicalPosition(of: node),
      node: node
    )
    return .visitChildren
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    visitNominal(
      node: node,
      name: node.name.text,
      attributes: node.attributes,
      modifiers: node.modifiers,
      isGeneric: node.genericParameterClause != nil,
      declaration: DeclSyntax(node)
    )
    return .visitChildren
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    visitNominal(
      node: node,
      name: node.name.text,
      attributes: node.attributes,
      modifiers: node.modifiers,
      isGeneric: node.genericParameterClause != nil,
      declaration: DeclSyntax(node)
    )
    return .visitChildren
  }

  override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
    visitNominal(
      node: node,
      name: node.name.text,
      attributes: node.attributes,
      modifiers: node.modifiers,
      isGeneric: node.genericParameterClause != nil,
      declaration: DeclSyntax(node)
    )
    return .visitChildren
  }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    visitNominal(
      node: node,
      name: node.name.text,
      attributes: node.attributes,
      modifiers: node.modifiers,
      isGeneric: node.genericParameterClause != nil,
      declaration: DeclSyntax(node)
    )
    if let parameterlessCase = Self.firstParameterlessCase(in: node) {
      let name = node.name.text
      let position = Self.lexicalPosition(of: node)
      // The generated file sits at module scope, so a nested enumeration must be named through its parents.
      let qualifiedName = Self.qualifiedName(for: name, at: position)
      for key in Self.keys(for: name, at: position) {
        index.enumDefaults[key] = "\(qualifiedName).\(parameterlessCase)"
      }
    }
    return .visitChildren
  }
}

extension DeclarationCollector {

  /// Registers nominal type metadata and records any Previewable annotation.
  /// - Parameters:
  ///   - node: The syntax node used to determine lexical scope and source location.
  ///   - name: The declared type name.
  ///   - attributes: Attributes inspected for generation and global-actor annotations.
  ///   - modifiers: The declared access modifiers.
  ///   - isGeneric: Whether the type declares generic parameters.
  ///   - declaration: The declaration retained for feature generation.
  fileprivate func visitNominal(
    node: some SyntaxProtocol,
    name: String,
    attributes: AttributeListSyntax,
    modifiers: DeclModifierListSyntax,
    isGeneric: Bool,
    declaration: DeclSyntax
  ) {
    let position = Self.lexicalPosition(of: node)
    let keys = Self.keys(for: name, at: position)
    index.declaredTypes.formUnion(keys)
    let access = AccessLevel(modifiers: modifiers)
    for key in keys { index.typeAccess[key] = access }
    if isGeneric { index.genericTypes.formUnion(keys) }
    if attributes.contains(where: {
      guard case .attribute(let attribute) = $0 else { return false }
      return attribute.attributeName.trimmedDescription == "globalActor"
    }) {
      index.globalActors.formUnion(keys)
    }
    guard let annotated = Self.annotation(in: attributes) else { return }
    if annotated.annotation == .fake { index.fakeAnnotatedTypes.formUnion(keys) }
    record(annotated, declaration: declaration, name: name, position: position, node: node)
  }

  /// Indexes a protocol and records its qualified name when annotated for double generation.
  /// - Parameters:
  ///   - node: The protocol syntax retained for requirement lookup.
  ///   - name: The unqualified protocol name.
  ///   - position: The lexical scope used to qualify the name.
  fileprivate func register(
    protocol node: ProtocolDeclSyntax,
    named name: String,
    at position: LexicalPosition
  ) {
    for key in Self.keys(for: name, at: position) {
      index.protocols[key] = node
    }
    guard Self.annotation(in: node.attributes)?.annotation == .double else { return }
    let qualifiedName = Self.qualifiedName(for: name, at: position)
    index.annotatedProtocols[qualifiedName] = qualifiedName
  }

  /// Appends an annotation with its declaration and source location.
  /// - Parameters:
  ///   - annotated: The feature and original attribute syntax.
  ///   - declaration: The declaration to validate and generate.
  ///   - name: The declaration name used in diagnostics.
  ///   - position: The declaration's lexical scope or unsupported location.
  ///   - node: The syntax node that determines the diagnostic offset.
  fileprivate func record(
    _ annotated: (annotation: PreviewableAnnotation, attribute: AttributeSyntax),
    declaration: DeclSyntax,
    name: String,
    position: LexicalPosition,
    node: some SyntaxProtocol
  ) {
    index.annotations.append(
      AnnotatedDeclaration(
        annotation: annotated.annotation,
        attribute: annotated.attribute,
        declaration: declaration,
        name: name,
        position: position,
        fileIndex: fileIndex,
        absolutePosition: node.positionAfterSkippingLeadingTrivia
      )
    )
  }

  /// Returns the qualified lookup key for a declaration.
  /// - Parameters:
  ///   - name: The declaration's written name.
  ///   - position: The enclosing type scope, when supported.
  fileprivate static func keys(for name: String, at position: LexicalPosition) -> [String] {
    let qualifiedName = qualifiedName(for: name, at: position)
    return [qualifiedName]
  }

  /// Returns the declaration name prefixed by its enclosing types, as the generated file must spell it.
  fileprivate static func qualifiedName(for name: String, at position: LexicalPosition) -> String {
    guard case .emittable(let qualifier) = position, !qualifier.isEmpty else { return name }
    return (qualifier + [name]).joined(separator: ".")
  }

  /// Returns the first case that carries no associated value, wherever it appears in the declaration.
  fileprivate static func firstParameterlessCase(in node: EnumDeclSyntax) -> String? {
    for member in node.memberBlock.members {
      guard let caseDeclaration = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
      for element in caseDeclaration.elements where element.parameterClause == nil {
        return element.name.text
      }
    }
    return nil
  }

  /// Returns the Previewable attribute carried by a declaration, alongside the attribute as written.
  ///
  /// The attribute travels with the annotation because arguments such as `parameters:` are the generator's only
  /// description of a type it cannot read, and interpreting them belongs with generation rather than collection.
  fileprivate static func annotation(
    in attributes: AttributeListSyntax
  ) -> (annotation: PreviewableAnnotation, attribute: AttributeSyntax)? {
    for element in attributes {
      guard case .attribute(let attribute) = element,
        let annotation = PreviewableAnnotation(
          rawValue: attribute.attributeName.trimmedDescription.replacingOccurrences(of: "Mercury.", with: "")
        )
      else { continue }
      return (annotation, attribute)
    }
    return nil
  }

  /// Walks the parent chain to decide whether a declaration can be emitted, and under which enclosing types.
  fileprivate static func lexicalPosition(of node: some SyntaxProtocol) -> LexicalPosition {
    var qualifier: [String] = []
    var current = node.parent

    while let parent = current {
      if parent.is(ExtensionDeclSyntax.self) {
        return .unsupported(reason: "inside an extension")
      }
      if parent.is(IfConfigDeclSyntax.self) {
        return .unsupported(reason: "inside a #if block")
      }
      if parent.is(FunctionDeclSyntax.self)
        || parent.is(InitializerDeclSyntax.self)
        || parent.is(ClosureExprSyntax.self)
        || parent.is(AccessorDeclSyntax.self)
      {
        return .unsupported(reason: "inside a function body")
      }
      if let structure = parent.as(StructDeclSyntax.self) {
        qualifier.insert(structure.name.text, at: 0)
      } else if let classDeclaration = parent.as(ClassDeclSyntax.self) {
        qualifier.insert(classDeclaration.name.text, at: 0)
      } else if let enumeration = parent.as(EnumDeclSyntax.self) {
        qualifier.insert(enumeration.name.text, at: 0)
      } else if let actorDeclaration = parent.as(ActorDeclSyntax.self) {
        qualifier.insert(actorDeclaration.name.text, at: 0)
      }
      current = parent.parent
    }
    return .emittable(qualifier: qualifier)
  }
}
