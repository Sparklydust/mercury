//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Rejects a type whose own declarations would make the generated factory fail to compile.
enum PreviewableFakeValidator {

    /// Checks that the initializer the generated factory calls actually exists.
    ///
    /// The factory is emitted into an extension, so it can only reach an initializer the type already declares.
    /// Catching the mismatch here reports it on the annotated declaration instead of leaving the compiler to
    /// fail inside generated source the developer cannot open.
    static func validateInitializer(
        in members: MemberBlockItemListSyntax,
        of typeName: String,
        isClass: Bool,
        properties: [StoredProperty]
    ) throws {
        let initializers = members.compactMap { $0.decl.as(InitializerDeclSyntax.self) }
        guard isClass else {
            // A structure that declares no initializer keeps its memberwise one, which the factory matches.
            guard !initializers.isEmpty,
                  !initializers.contains(where: { accepts($0, properties: properties) })
            else { return }
            let labels = properties.map { "\($0.name):" }.joined()
            throw GenerationError.message(
                """
                @PreviewableFake cannot construct '\(typeName)': declaring an initializer suppresses the \
                memberwise one — add an accessible 'init(\(labels))' or move the initializer to an extension
                """
            )
        }
        guard initializers.isEmpty else {
            guard !initializers.contains(where: { accepts($0, properties: []) }) else { return }
            throw GenerationError.message(
                """
                @PreviewableFake cannot construct '\(typeName)': the generated initializer calls 'init()' \
                — declare an accessible parameterless initializer
                """
            )
        }
        // Without a declared initializer, a class only gets an implicit `init()` when nothing needs a value.
        guard let uninitialized = PreviewableStoredPropertyCollector.firstPropertyWithoutInitialValue(in: members) else { return }
        throw GenerationError.message(
            """
            @PreviewableFake cannot construct '\(typeName)': '\(uninitialized)' has no initial value, so the \
            class has no 'init()' to call — give it a default value or declare a parameterless initializer
            """
        )
    }

    /// Returns whether an initializer can be called with the supplied property labels in order.
    private static func accepts(_ initializer: InitializerDeclSyntax, properties: [StoredProperty]) -> Bool {
        guard !initializer.modifiers.isFileScoped, initializer.optionalMark == .none else { return false }
        let parameters = Array(initializer.signature.parameterClause.parameters)
        guard parameters.count >= properties.count else { return false }
        for (parameter, property) in zip(parameters, properties) where parameter.firstName.text != property.name {
            return false
        }
        return parameters.dropFirst(properties.count).allSatisfy { $0.defaultValue != .none }
    }

    /// Checks that a factory never exposes a type less visible than itself.
    ///
    /// A `public` structure may hold a property of an `internal` type — Swift only makes its memberwise initializer
    /// `internal` in turn. The generated factory has no such fallback: it takes the type's access, so the mismatch
    /// becomes an error in generated source unless it is caught here.
    static func validateFactoryAccess(
        of typeName: String,
        access: AccessLevel,
        properties: [StoredProperty],
        index: ModuleIndex
    ) throws {
        guard access > .internal else { return }
        for property in properties {
            for name in property.type.writtenTypeNames {
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
}
