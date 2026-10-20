//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Rejects a type whose own declarations would make the generated factory fail to compile.
enum PreviewableFakeValidator {

  /// Checks that the initializer the generated factory calls actually exists.
  ///
  /// Accepts a matching accessible synchronous initializer or an applicable implicit initializer.
  /// - Parameters:
  ///   - members: The stored properties and initializers declared directly in the type.
  ///   - typeName: The type name used in diagnostics.
  ///   - isClass: Whether construction requires a parameterless class initializer.
  ///   - properties: The factory inputs in initializer argument order.
  ///   - index: Module declarations used to resolve equivalent parameter type spellings.
  ///   - inheritance: Inherited types checked before accepting an implicit class initializer.
  /// - Returns: Whether the selected initializer throws.
  /// - Throws: `GenerationError` when no usable initializer exists or multiple initializers match.
  static func validateInitializer(
    in members: MemberBlockItemListSyntax,
    of typeName: String,
    isClass: Bool,
    properties: [StoredProperty],
    index: ModuleIndex,
    inheritance: InheritanceClauseSyntax? = nil
  ) throws -> Bool {

    let scope = typeName.split(separator: ".").map(String.init)
    let initializers = members.compactMap { $0.decl.as(InitializerDeclSyntax.self) }
    let candidates = initializers.filter {
      accepts($0, properties: isClass ? [] : properties, index: index, scope: scope)
    }
    if !candidates.isEmpty {
      guard candidates.count == 1 else {
        throw GenerationError.message("@PreviewableFake cannot choose between matching initializers of '\(typeName)'")
      }
      try validateAttributes(of: candidates[0])
      return candidates[0].signature.effectSpecifiers?.throwsClause != nil
    }

    if !isClass {
      return try validateImplicitStructure(
        members: members,
        initializers: initializers,
        properties: properties,
        typeName: typeName,
        index: index,
        scope: scope
      )
    }

    return try validateClassInitializer(
      members: members,
      initializers: initializers,
      inheritance: inheritance,
      typeName: typeName,
      index: index,
      scope: scope
    )
  }

  private static func validateImplicitStructure(
    members: MemberBlockItemListSyntax,
    initializers: [InitializerDeclSyntax],
    properties: [StoredProperty],
    typeName: String,
    index: ModuleIndex,
    scope: [String]
  ) throws -> Bool {
    try validateHiddenProperties(in: members)
    // A structure that declares no initializer keeps its memberwise one, which the factory matches.
    guard !initializers.isEmpty,
          !initializers.contains(where: { accepts($0, properties: properties, index: index, scope: scope) })
    else { return false }

    let labels = properties.map { "\($0.name):" }.joined()
    throw GenerationError.message(
      """
      @PreviewableFake cannot construct '\(typeName)': declaring an initializer suppresses the \
      memberwise one — add an accessible 'init(\(labels))' or move the initializer to an extension
      """
    )
  }

  private static func validateClassInitializer(
    members: MemberBlockItemListSyntax,
    initializers: [InitializerDeclSyntax],
    inheritance: InheritanceClauseSyntax?,
    typeName: String,
    index: ModuleIndex,
    scope: [String]
  ) throws -> Bool {
    guard initializers.isEmpty else {
      guard !initializers.contains(where: { accepts($0, properties: [], index: index, scope: scope) })
      else { return false }

      throw GenerationError.message(
        """
        @PreviewableFake cannot construct '\(typeName)': the generated initializer calls 'init()' \
        — declare an accessible parameterless initializer
        """
      )
    }

    try validateInheritedInitializer(inheritance, typeName: typeName, index: index, scope: scope)

    // A root class only gets an implicit `init()` when every stored property has a value.
    guard let uninitialized = PreviewableStoredPropertyCollector.firstPropertyWithoutInitialValue(in: members)
    else { return false }

    throw GenerationError.message(
      """
      @PreviewableFake cannot construct '\(typeName)': '\(uninitialized)' has no initial value, so the \
      class has no 'init()' to call — give it a default value or declare a parameterless initializer
      """
    )
  }

  private static func validateInheritedInitializer(
    _ inheritance: InheritanceClauseSyntax?,
    typeName: String,
    index: ModuleIndex,
    scope: [String]
  ) throws {
    for inherited in inheritance?.inheritedTypes ?? [] {
      var type = inherited.type

      while let attributed = type.as(AttributedTypeSyntax.self) {
        type = attributed.baseType
      }
      let name = type.trimmedDescription
      let isProtocol: Bool

      if let resolved = index.resolve(name, scope: scope) {
        isProtocol = index.protocols[resolved] != nil
      } else {
        isProtocol = ["Sendable", "Swift.Sendable", "AnyObject", "Swift.AnyObject"].contains(name)
      }

      guard isProtocol else {
        throw GenerationError.message(
          "@PreviewableFake cannot verify inherited 'init()' for '\(typeName)' "
            + "— declare an accessible parameterless initializer"
        )
      }
    }
  }

  /// Returns whether an initializer can be called with the supplied property labels in order.
  private static func accepts(
    _ initializer: InitializerDeclSyntax,
    properties: [StoredProperty],
    index: ModuleIndex,
    scope: [String]
  ) -> Bool {
    guard !initializer.modifiers.isFileScoped, initializer.optionalMark == .none,
          initializer.signature.effectSpecifiers?.asyncSpecifier == nil,
          initializer.genericParameterClause == nil
    else { return false }

    let parameters = Array(initializer.signature.parameterClause.parameters)

    guard parameters.count >= properties.count else { return false }
    for (parameter, property) in zip(parameters, properties) {
      guard parameter.firstName.text == property.name,
            InitializerTypeResolver.identity(of: parameter.type, index: index, scope: scope)
            == InitializerTypeResolver.identity(of: property.type, index: index, scope: scope)
      else { return false }
    }

    return parameters.dropFirst(properties.count).allSatisfy { $0.defaultValue != .none }
  }

  /// Checks that a factory never exposes a type less visible than itself.
  ///
  /// A `public` structure may hold a property of an `internal` type — Swift only makes its memberwise initializer
  /// `internal` in turn. The generated factory has no such fallback: it takes the type's access, so the mismatch
  /// becomes an error in generated source unless it is caught here.
  /// - Parameters:
  ///   - typeName: The type receiving the factory.
  ///   - access: The factory's intended visibility.
  ///   - properties: The parameter types to check.
  ///   - index: The declared access levels available in the module.
  /// - Throws: `GenerationError` when a recognized parameter type is less visible than the factory.
  static func validateFactoryAccess(
    of typeName: String,
    access: AccessLevel,
    properties: [StoredProperty],
    index: ModuleIndex
  ) throws {
    guard access > .internal else { return }
    for property in properties {
      for name in property.type.qualifiedTypeNames {
        guard let declared = index.typeAccess[name], declared < access else { continue }

        throw GenerationError.message(
          """
          @PreviewableFake cannot generate a \(access.keyword) factory for '\(typeName)': its \
          '\(property.name)' parameter uses the \(declared.keyword) type '\(name)' \
          — raise '\(name)' to \(access.keyword)
          """
        )
      }
    }
  }

  /// Rejects initializer attributes whose isolation or other effects are not represented by the factory.
  /// - Parameter initializer: The selected accessible initializer.
  /// - Throws: `GenerationError` when an attribute requires unsupported initializer-specific behavior.
  private static func validateAttributes(of initializer: InitializerDeclSyntax) throws {
    let supported: Set<String> = ["available", "inlinable", "usableFromInline", "_transparent", "discardableResult"]

    for element in initializer.attributes {
      guard case .attribute(let attribute) = element else { continue }
      let name = attribute.attributeName.trimmedDescription

      guard !supported.contains(name) else { continue }
      throw GenerationError.message(
        "@PreviewableFake does not support initializer attribute '@\(name)' — declare actor isolation on the type"
      )
    }
  }

  /// Rejects hidden stored inputs when no accessible explicit structure initializer handles them.
  /// - Parameter members: The declarations directly contained in the structure.
  /// - Throws: `GenerationError` when the implicit memberwise initializer would require a hidden input.
  private static func validateHiddenProperties(in members: MemberBlockItemListSyntax) throws {
    for member in members {
      guard let variable = member.decl.as(VariableDeclSyntax.self), variable.modifiers.isFileScoped,
            !variable.modifiers.isStatic
      else { continue }

      for binding in variable.bindings {
        guard PreviewableStoredPropertyCollector.isStored(binding),
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              variable.bindingSpecifier.text == "var" || binding.initializer == nil
        else { continue }

        throw GenerationError.message(
          "@PreviewableFake cannot construct this type: private property '\(identifier.identifier.text)' "
            + "appears in the memberwise initializer — give it a default value or provide an accessible initializer"
        )
      }
    }
  }
}
