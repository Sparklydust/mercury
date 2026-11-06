//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

/// Retains validated protocol metadata used by every stage of double generation.
struct DoubleDefinition {

  let declaration: ProtocolDeclSyntax
  let qualifiedName: String
  let index: ModuleIndex
  let isolated: Bool
  let sendable: Bool
  let associated: DoubleAssociatedTypes
  let members: [MemberBlockItemSyntax]

  var access: String { index.accessPrefix(for: qualifiedName) }
  var doubleName: String { PreviewableDoubleNaming.doubleName(for: declaration.name.text) }
  var sharedPreview: Bool { sendable && associated.parameters.isEmpty }
  var isolation: String { Self.protocolIsolation(declaration, index: index) }

  /// Validates a protocol and resolves its isolation, sendability, and associated types.
  /// - Parameters:
  ///   - declaration: The annotated protocol.
  ///   - qualifiedName: Its name including enclosing declaration names.
  ///   - index: Module declarations used to resolve access, inheritance, and aliases.
  /// - Throws: `GenerationError` for inaccessible declarations, name conflicts, or unsupported requirements.
  static func resolve(
    from declaration: ProtocolDeclSyntax,
    qualifiedName: String,
    index: ModuleIndex
  ) throws -> Self {
    try validateDeclaration(declaration, index: index)
    let isolated = DoubleStorageBuilder.isIsolated(declaration, index: index)
    let sendable = isolated || GenericResponseValidator.impliesSendable(
      TypeSyntax(IdentifierTypeSyntax(name: .identifier(qualifiedName))),
      index: index
    )
    let original = try flattenedMembers(of: declaration, index: index)
    let associated = try DoubleAssociatedTypes(
      declaration: declaration,
      members: original,
      index: index,
      isolated: isolated,
      sendable: sendable
    )

    return Self(
      declaration: declaration,
      qualifiedName: qualifiedName,
      index: index,
      isolated: isolated,
      sendable: sendable,
      associated: associated,
      members: substitutedMembers(original, associated: associated)
    )
  }

  /// Collects canonical requirements after associated-type substitution.
  /// - Throws: `GenerationError` for unsupported or conflicting requirements.
  func requirements() throws -> [DoubleRequirement] {
    try DoubleRequirement.collect(
      members,
      index: index,
      scope: qualifiedName.split(separator: ".").map(String.init),
      defaultIsolation: isolation
    )
  }

  private static func validateDeclaration(
    _ declaration: ProtocolDeclSyntax,
    index: ModuleIndex
  ) throws {
    guard !declaration.modifiers.isFileScoped else {
      throw GenerationError.message("@PreviewableDouble cannot access a private or fileprivate protocol")
    }
    let name = PreviewableDoubleNaming.doubleName(for: declaration.name.text)

    guard index.typeAccess[name] == nil else {
      throw GenerationError.message(
        "@PreviewableDouble generated type '\(name)' conflicts with an existing declaration"
      )
    }
  }

  private static func flattenedMembers(
    of declaration: ProtocolDeclSyntax,
    index: ModuleIndex
  ) throws -> [MemberBlockItemSyntax] {
    var visited: Set<String> = []
    return try PreviewableRequirementFlattener.requirements(
      of: declaration,
      index: index,
      visited: &visited
    )
  }

  private static func substitutedMembers(
    _ original: [MemberBlockItemSyntax],
    associated: DoubleAssociatedTypes
  ) -> [MemberBlockItemSyntax] {
    let rewriter = DoubleTypeSubstitution(associated.bindings)

    return original
      .filter { !$0.decl.is(AssociatedTypeDeclSyntax.self) }
      .map { rewriter.rewrite($0).cast(MemberBlockItemSyntax.self) }
  }

  /// Finds the protocol's declared or inherited global actor for its scoped static state.
  private static func protocolIsolation(
    _ declaration: ProtocolDeclSyntax,
    index: ModuleIndex,
    visited: Set<String> = []
  ) -> String {
    let name = index.protocols.first { $0.value.id == declaration.id }?.key ?? declaration.name.text

    guard !visited.contains(name) else { return "" }
    let scope = name.split(separator: ".").map(String.init)
    let own = DoubleStorageBuilder.isolationAttributes(in: declaration.attributes, index: index, scope: scope)

    guard own.isEmpty else { return own }

    for inherited in declaration.inheritanceClause?.inheritedTypes ?? [] {
      guard let key = index.resolve(inherited.type.trimmedDescription, scope: scope),
            let base = index.protocols[key]
      else { continue }

      let isolation = protocolIsolation(base, index: index, visited: visited.union([name]))
      guard !isolation.isEmpty else { continue }
      return isolation
    }
    return ""
  }
}
