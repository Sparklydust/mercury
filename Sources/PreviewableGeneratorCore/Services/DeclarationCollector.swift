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
    recordGlobalName(name, at: node)
    register(protocol: node, named: name, at: position)
    if let annotated = Self.annotation(in: node.attributes) {
      record(annotated, declaration: DeclSyntax(node), name: name, position: position, node: node)
    }

    return .visitChildren
  }

  override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
    recordGlobalName(node.name.text, at: node)
    let name = Self.qualifiedName(for: node.name.text, at: Self.lexicalPosition(of: node))
    index.typeAccess[name] = Self.effectiveAccess(of: node, modifiers: node.modifiers)

    if node.genericParameterClause == nil {
      index.typeAliases[name] = node.initializer.value
    }
    return .visitChildren
  }

  override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
    for binding in node.bindings {
      for token in binding.pattern.tokens(viewMode: .sourceAccurate) {
        if case .identifier(let name) = token.tokenKind {
          recordGlobalName(name, at: node)
        }
      }
    }
    return .visitChildren
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    if node.signature.parameterClause.parameters.isEmpty {
      recordGlobalName(node.name.text, at: node)
    }
    return .visitChildren
  }

  override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
    guard let annotated = Self.annotation(in: node.attributes) else { return .visitChildren }
    // The generator never sees the extended type, so its spelling in the extension is the only name there is.
    let name = node.extendedType.trimmedDescription

    if annotated.annotation == .fake {
      index.fakeAnnotatedTypes.insert(name)
    }

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
    collectNominal(node)
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    collectNominal(node)
  }

  override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
    collectNominal(node)
  }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    let result = collectNominal(node)
    recordEnumDefault(node)
    return result
  }
}

private extension DeclarationCollector {

  /// Records names outside member blocks, functions, and closures, including conditional file-scope declarations.
  /// - Parameters:
  ///   - name: The declared name, optionally escaped with backticks.
  ///   - node: The declaration whose enclosing scopes are inspected.
  private func recordGlobalName(
    _ name: String,
    at node: some SyntaxProtocol
  ) {
    var current = node.parent

    while let parent = current {
      if parent.is(MemberBlockSyntax.self)
         || parent.is(CodeBlockSyntax.self)
         || parent.is(ClosureExprSyntax.self) {
        return
      }
      current = parent.parent
    }
    index.globalNames.insert(name.replacingOccurrences(of: "`", with: ""))
  }

  private func recordEnumDefault(_ node: EnumDeclSyntax) {
    guard let firstCase = Self.firstParameterlessCase(in: node) else { return }

    let name = node.name.text
    let position = Self.lexicalPosition(of: node)
    let qualifiedName = Self.qualifiedName(for: name, at: position)

    for key in Self.keys(for: name, at: position) {
      index.enumDefaults[key] = "\(qualifiedName).\(firstCase)"
    }
  }

  private func collectNominal<Node>(
    _ node: Node
  ) -> SyntaxVisitorContinueKind where
    Node: DeclGroupSyntax,
    Node: NamedDeclSyntax,
    Node: WithAttributesSyntax,
    Node: WithModifiersSyntax,
    Node: WithGenericParametersSyntax {

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

  /// Registers nominal type metadata and records any Previewable annotation.
  /// - Parameters:
  ///   - node: The syntax node used to determine lexical scope and source location.
  ///   - name: The declared type name.
  ///   - attributes: Attributes inspected for generation and global-actor annotations.
  ///   - modifiers: The declared access modifiers.
  ///   - isGeneric: Whether the type declares generic parameters.
  ///   - declaration: The declaration retained for feature generation.
  func visitNominal(
    node: some SyntaxProtocol,
    name: String,
    attributes: AttributeListSyntax,
    modifiers: DeclModifierListSyntax,
    isGeneric: Bool,
    declaration: DeclSyntax
  ) {
    recordGlobalName(name, at: node)
    let position = Self.lexicalPosition(of: node)
    let keys = Self.keys(for: name, at: position)
    index.declaredTypes.formUnion(keys)
    let access = Self.effectiveAccess(of: node, modifiers: modifiers)

    for key in keys {
      index.typeAccess[key] = access
    }
    if isGeneric {
      index.genericTypes.formUnion(keys)
    }

    if attributes.contains(where: {
      guard case .attribute(let attribute) = $0 else { return false }
      return attribute.attributeName.trimmedDescription == "globalActor"
    }) {
      index.globalActors.formUnion(keys)
    }

    guard let annotated = Self.annotation(in: attributes) else { return }
    if annotated.annotation == .fake {
      index.fakeAnnotatedTypes.formUnion(keys)
    }
    record(annotated, declaration: declaration, name: name, position: position, node: node)
  }

  /// Indexes a protocol and records its qualified name when annotated for double generation.
  /// - Parameters:
  ///   - node: The protocol syntax retained for requirement lookup.
  ///   - name: The unqualified protocol name.
  ///   - position: The lexical scope used to qualify the name.
  func register(
    protocol node: ProtocolDeclSyntax,
    named name: String,
    at position: LexicalPosition
  ) {
    for key in Self.keys(for: name, at: position) {
      index.protocols[key] = node
      index.typeAccess[key] = Self.effectiveAccess(of: node, modifiers: node.modifiers)
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
  func record(
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
  static func keys(
    for name: String,
    at position: LexicalPosition
  ) -> [String] {
    let qualifiedName = qualifiedName(for: name, at: position)
    return [qualifiedName]
  }

  /// Returns the declaration name prefixed by its enclosing types, as the generated file must spell it.
  static func qualifiedName(
    for name: String,
    at position: LexicalPosition
  ) -> String {
    guard case .emittable(let qualifier) = position, !qualifier.isEmpty else { return name }
    return (qualifier + [name]).joined(separator: ".")
  }

  /// Returns the first case that carries no associated value, wherever it appears in the declaration.
  static func firstParameterlessCase(in node: EnumDeclSyntax) -> String? {
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
  static func annotation(
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
  static func lexicalPosition(of node: some SyntaxProtocol) -> LexicalPosition {
    var qualifier: [String] = []
    var current = node.parent

    while let parent = current {
      if let reason = unsupportedScopeReason(in: parent) {
        return .unsupported(reason: reason)
      }
      if let name = nominalName(in: parent) {
        qualifier.insert(name, at: 0)
      }
      current = parent.parent
    }

    return .emittable(qualifier: qualifier)
  }

  private static func unsupportedScopeReason(in parent: Syntax) -> String? {
    if let modifiers = typeModifiers(of: parent), modifiers.isFileScoped {
      return "inside a private or fileprivate type"
    }
    return switch parent.as(SyntaxEnum.self) {
    case .extensionDecl: "inside an extension"
    case .ifConfigDecl: "inside a #if block"
    case .functionDecl, .initializerDecl, .closureExpr, .accessorDecl: "inside a function body"
    default: nil
    }
  }

  private static func nominalName(in node: Syntax) -> String? {
    switch node.as(SyntaxEnum.self) {
    case .structDecl(let declaration): declaration.name.text
    case .classDecl(let declaration): declaration.name.text
    case .enumDecl(let declaration): declaration.name.text
    case .actorDecl(let declaration): declaration.name.text
    default: nil
    }
  }

  /// Returns the narrowest access level among a declaration and its enclosing types.
  /// - Parameters:
  ///   - node: The declaration whose parent chain is inspected.
  ///   - modifiers: The declaration's own access modifiers.
  private static func effectiveAccess(
    of node: some SyntaxProtocol,
    modifiers: DeclModifierListSyntax
  ) -> AccessLevel {
    var access = AccessLevel(modifiers: modifiers)
    var current = node.parent

    while let parent = current {
      if let modifiers = typeModifiers(of: parent) {
        access = min(access, AccessLevel(modifiers: modifiers))
      }
      current = parent.parent
    }

    return access
  }

  /// Returns access modifiers for a nominal type ancestor.
  /// - Parameter node: The syntax ancestor to inspect.
  private static func typeModifiers(of node: Syntax) -> DeclModifierListSyntax? {
    switch node.as(SyntaxEnum.self) {
    case .structDecl(let declaration): declaration.modifiers
    case .classDecl(let declaration): declaration.modifiers
    case .enumDecl(let declaration): declaration.modifiers
    case .actorDecl(let declaration): declaration.modifiers
    case .protocolDecl(let declaration): declaration.modifiers
    default: nil
    }
  }
}
