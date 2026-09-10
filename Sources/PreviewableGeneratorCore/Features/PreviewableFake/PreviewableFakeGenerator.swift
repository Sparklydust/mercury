//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Generates the fake factory `@PreviewableFake` derives from a type declared in this module.
enum PreviewableFakeGenerator: PreviewableFeatureProtocol {

    static let annotation: PreviewableAnnotation = .fake

    static func conflict(in annotations: [AnnotatedDeclaration]) -> GenerationFailure? {
        // An owned type carries one annotation at most, but an extension can be annotated in any number of files.
        var fakedTypes: Set<String> = []
        for annotation in annotations where annotation.annotation == .fake {
            guard !fakedTypes.insert(annotation.qualifiedName).inserted else { continue }
            return GenerationFailure(
                annotation: annotation,
                message: """
                '\(annotation.qualifiedName)' is annotated with @PreviewableFake more than once \
                — keep a single annotation
                """
            )
        }
        return .none
    }

    static func generate(
        from annotation: AnnotatedDeclaration,
        index: ModuleIndex,
        resolver: inout DefaultValueResolver
    ) throws -> GeneratedPreviewable {
        let generated = try fake(from: annotation, index: index, resolver: &resolver)
        return GeneratedPreviewable(debug: [generated.debug], release: [generated.release])
    }

    private static func fake(
        from annotation: AnnotatedDeclaration,
        index: ModuleIndex,
        resolver: inout DefaultValueResolver
    ) throws -> GeneratedFake {
        if let extended = annotation.declaration.as(ExtensionDeclSyntax.self) {
            return try PreviewableExternalFakeGenerator.generate(from: annotation, in: extended, resolver: &resolver)
        }

        let members: MemberBlockItemListSyntax
        let modifiers: DeclModifierListSyntax
        let access: String
        let isClass: Bool
        let genericClause: GenericParameterClauseSyntax?

        if let structure = annotation.declaration.as(StructDeclSyntax.self) {
            members = structure.memberBlock.members
            modifiers = structure.modifiers
            access = structure.modifiers.accessPrefix
            genericClause = structure.genericParameterClause
            isClass = false
        } else if let classDeclaration = annotation.declaration.as(ClassDeclSyntax.self) {
            members = classDeclaration.memberBlock.members
            modifiers = classDeclaration.modifiers
            access = classDeclaration.modifiers.accessPrefix
            genericClause = classDeclaration.genericParameterClause
            isClass = true
        } else {
            throw GenerationError.message(
                "@PreviewableFake can only be applied to a structure or class"
            )
        }

        guard annotation.attribute.arguments == nil else {
            throw GenerationError.message(
                """
                @PreviewableFake reads the stored properties of a type declared in this module \
                — remove 'parameters:'
                """
            )
        }

        let genericParameters = Set(genericClause?.parameters.map(\.name.text) ?? [])
        let typeName = annotation.qualifiedName
        let genericSuffix = genericClause.map { clause in
            "<\(clause.parameters.map(\.name.text).joined(separator: ", "))>"
        } ?? String()
        let returnType = typeName + genericSuffix

        let properties = try PreviewableStoredPropertyCollector.storedProperties(in: members)
        if isClass && properties.contains(where: { !$0.isMutable }) {
            throw GenerationError.message(
                "@PreviewableFake classes require mutable fake properties and an accessible init()"
            )
        }
        try PreviewableFakeValidator.validateInitializer(in: members, of: typeName, isClass: isClass, properties: properties)
        try PreviewableFakeValidator.validateFactoryAccess(
            of: typeName,
            access: AccessLevel(modifiers: modifiers),
            properties: properties,
            index: index
        )

        return try PreviewableFakeFactoryBuilder.factory(
            typeName: typeName,
            returnType: returnType,
            access: access,
            properties: properties,
            genericParameters: genericParameters,
            declaresConvenienceInitializer: isClass && !properties.isEmpty,
            resolver: &resolver
        )
    }
}
