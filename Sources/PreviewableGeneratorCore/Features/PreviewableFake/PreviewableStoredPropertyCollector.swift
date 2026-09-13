//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Reads the stored properties a generated factory must take an argument for.
enum PreviewableStoredPropertyCollector {

    /// Returns the stored properties a fake factory can set.
    ///
    /// Private and file-private properties are deliberately excluded — reaching them would defeat the access
    /// control the developer asked for. They only block generation when they would also appear in the
    /// memberwise initializer, which the generated extension could then not call.
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
                guard binding.accessorBlock == .none,
                      let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
                else { continue }

                let isMutable = variable.bindingSpecifier.tokenKind == .keyword(.var)
                let hasInitializer = binding.initializer != .none

                if isHidden {
                    guard hasInitializer, !isMutable else {
                        throw GenerationError.message(
                            """
                            @PreviewableFake cannot construct this type: private property \
                            '\(identifier.identifier.text)' appears in the memberwise initializer \
                            — give it a default value or provide an accessible initializer
                            """
                        )
                    }
                    continue
                }

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
                guard binding.accessorBlock == .none,
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

    private static func inferredType(from binding: PatternBindingSyntax) -> TypeSyntax? {
        if let type = binding.typeAnnotation?.type { return type }
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
}
