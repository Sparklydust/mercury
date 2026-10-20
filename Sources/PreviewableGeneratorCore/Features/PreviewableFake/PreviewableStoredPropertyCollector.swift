//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Reads the stored properties a generated factory must take an argument for.
enum PreviewableStoredPropertyCollector {

  /// Returns the stored properties a fake factory can set.
  ///
  /// Hidden properties are omitted. Initializer validation checks whether construction can initialize them.
  /// - Parameter members: The declarations directly contained in the annotated type.
  /// - Throws: `GenerationError` for properties without a resolvable type.
  static func storedProperties(
    in members: MemberBlockItemListSyntax
  ) throws -> [StoredProperty] {
    var properties: [StoredProperty] = []

    for member in members {
      guard let variable = member.decl.as(VariableDeclSyntax.self),
            !variable.modifiers.isStatic
      else { continue }

      let isHidden = variable.modifiers.isFileScoped

      for binding in variable.bindings {
        guard isStored(binding),
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
        else { continue }

        let isMutable = variable.bindingSpecifier.tokenKind == .keyword(.var)
        let hasInitializer = binding.initializer != .none

        // Initializer validation decides whether omitted hidden properties can be initialized safely.
        guard !isHidden else { continue }

        guard isMutable || !hasInitializer else { continue }
        guard let type = inferredType(from: binding) else {
          throw GenerationError.message(
            """
            @PreviewableFake requires an explicit or inferable type for \
            '\(identifier.identifier.text)'
            """
          )
        }
        properties.append(
          StoredProperty(
            name: identifier.identifier.text,
            type: type,
            isMutable: isMutable
          )
        )
      }
    }
    return properties
  }

  /// Returns the first stored property that the compiler cannot give an implicit initial value.
  static func firstPropertyWithoutInitialValue(in members: MemberBlockItemListSyntax) -> String? {
    for member in members {
      guard let variable = member.decl.as(VariableDeclSyntax.self),
            !variable.modifiers.isStatic
      else { continue }

      let isMutable = variable.bindingSpecifier.tokenKind == .keyword(.var)

      for binding in variable.bindings {
        guard isStored(binding),
              binding.initializer == .none,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
        else { continue }
        // Only a mutable optional is implicitly `nil`.
        let isNilDefaulted = binding.typeAnnotation.map(\.type.isOptional) ?? false

        guard !(isMutable && isNilDefaulted) else { continue }
        return identifier.identifier.text
      }
    }
    return .none
  }

  /// Returns an explicit type or infers one from a direct call name or supported scalar literal.
  /// - Parameter binding: The stored property binding to inspect.
  private static func inferredType(from binding: PatternBindingSyntax) -> TypeSyntax? {
    if let type = binding.typeAnnotation?.type {
      return type
    }

    guard let initializer = binding.initializer?.value else { return .none }

    if let call = initializer.as(FunctionCallExprSyntax.self),
       let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
      return TypeSyntax(IdentifierTypeSyntax(name: .identifier(reference.baseName.text)))
    }

    let inferred: String?

    switch initializer.kind {
    case .stringLiteralExpr: inferred = "String"
    case .booleanLiteralExpr: inferred = "Bool"
    case .floatLiteralExpr: inferred = "Double"
    case .integerLiteralExpr: inferred = "Int"
    default: inferred = .none
    }

    return inferred.map { TypeSyntax(IdentifierTypeSyntax(name: .identifier($0))) }
  }

  /// Observers belong to stored properties; getters and setters do not.
  static func isStored(_ binding: PatternBindingSyntax) -> Bool {
    guard let block = binding.accessorBlock else { return true }
    guard case .accessors(let accessors) = block.accessors else { return false }
    return accessors.allSatisfy { ["willSet", "didSet"].contains($0.accessorSpecifier.text) }
  }
}
