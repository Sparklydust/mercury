//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Generates the test double `@PreviewableDouble` derives from a protocol.
enum PreviewableDoubleGenerator: PreviewableFeatureProtocol {

    static let annotation: PreviewableAnnotation = .double

    static func conflict(in annotations: [AnnotatedDeclaration]) -> GenerationFailure? {
        var owners: [String: String] = [:]
        for annotation in annotations where annotation.annotation == .double {
            let doubleName = PreviewableDoubleNaming.doubleName(for: annotation.name)
            if let existing = owners[doubleName] {
                return GenerationFailure(
                    annotation: annotation,
                    message: """
                    '\(annotation.name)' and '\(existing)' both generate '\(doubleName)' \
                    — rename one of the protocols
                    """
                )
            }
            owners[doubleName] = annotation.name
        }
        return .none
    }

    static func generate(
        from annotation: AnnotatedDeclaration,
        index: ModuleIndex,
        resolver: inout DefaultValueResolver
    ) throws -> GeneratedPreviewable {
        guard let declaration = annotation.declaration.as(ProtocolDeclSyntax.self) else {
            throw GenerationError.message("@PreviewableDouble can only be applied to a protocol")
        }
        let generated = try double(
            from: declaration,
            qualifiedName: annotation.qualifiedName,
            index: index,
            resolver: &resolver
        )
        return GeneratedPreviewable(
            debug: [generated.declaration],
            unconditional: [generated.previewConfiguration]
        )
    }

    private static func double(
        from declaration: ProtocolDeclSyntax,
        qualifiedName: String,
        index: ModuleIndex,
        resolver: inout DefaultValueResolver
    ) throws -> GeneratedDouble {
        guard declaration.primaryAssociatedTypeClause == .none,
              declaration.genericWhereClause == .none
        else {
            throw GenerationError.message(
                "@PreviewableDouble does not support protocols with associated types or generic constraints"
            )
        }

        let protocolName = declaration.name.text
        let doubleName = PreviewableDoubleNaming.doubleName(for: protocolName)
        let access = declaration.modifiers.accessPrefix
        var visited: Set<String> = []
        let members = try PreviewableRequirementFlattener.requirements(of: declaration, index: index, visited: &visited)

        var stubDeclarations: [String] = []
        var requirementDeclarations: [String] = []
        var methodSignatures: [String: String] = [:]
        var propertyNames: Set<String> = []

        for member in members {
            if let variable = member.decl.as(VariableDeclSyntax.self) {
                for property in try PreviewableDoubleMemberBuilder.propertyDeclarations(
                    from: variable,
                    access: access,
                    seen: &propertyNames,
                    resolver: &resolver
                ) {
                    stubDeclarations.append(property.stub)
                    requirementDeclarations.append(property.requirement)
                }
                continue
            }
            if let function = member.decl.as(FunctionDeclSyntax.self) {
                let name = function.name.text
                let signature = function.signature.trimmedDescription
                if let inherited = methodSignatures[name] {
                    // A refinement may restate a requirement it inherits; only distinct shapes are ambiguous.
                    guard inherited != signature else { continue }
                    throw GenerationError.message(
                        "@PreviewableDouble does not support overloaded requirement '\(name)'"
                    )
                }
                methodSignatures[name] = signature
                let method = try PreviewableDoubleMemberBuilder.methodDeclaration(
                    from: function,
                    access: access,
                    resolver: &resolver
                )
                stubDeclarations.append(contentsOf: method.stubs)
                requirementDeclarations.append(method.requirement)
                continue
            }
            if let initializer = member.decl.as(InitializerDeclSyntax.self) {
                if let requirement = try PreviewableDoubleMemberBuilder.initializerDeclaration(from: initializer, access: access) {
                    requirementDeclarations.append(requirement)
                }
                continue
            }
            if member.decl.is(AssociatedTypeDeclSyntax.self)
                || member.decl.is(SubscriptDeclSyntax.self) {
                throw GenerationError.message(
                    "@PreviewableDouble does not support associated types or subscripts"
                )
            }
        }

        var sections: [String] = []
        if !stubDeclarations.isEmpty {
            sections.append(
                (["// Mock values"] + stubDeclarations).joined(separator: "\n")
            )
        }
        sections.append(
            [
                "// Preview value",
                "/// The shared double used by previews.",
                "///",
                "/// Instantiated once as a dummy, but can act as a mock or spy",
                "/// depending on the configured stubs and tracked calls when used.",
                "/// - Important: Use this value only from SwiftUI previews.",
                "\(access)nonisolated static let preview = \(doubleName)()"
            ].joined(separator: "\n")
        )
        sections.append("\(access)nonisolated init() {}")
        sections.append(
            [
                "// Spy values",
                "/// The protocol method names invoked on this double.",
                "\(access)private(set) var calledMethods: [String] = []",
                "/// The arguments captured for each invocation of a protocol method, in call order.",
                "\(access)private(set) var passedParameters: [String: [[Any?]]] = [:]"
            ].joined(separator: "\n")
        )
        if !requirementDeclarations.isEmpty {
            sections.append(
                (["// Protocol requirements"] + requirementDeclarations)
                    .joined(separator: "\n")
            )
        }

        let body = sections.map { $0.indented(by: 2) }.joined(separator: "\n\n")
        let generatedDeclaration = """
      /// A test double for `\(protocolName)`.
      ///
      /// Configure stubs and inspect recorded calls when testing protocol consumers.
      /// - Important: Available only in Debug builds.
      \(access)final class \(doubleName): \(qualifiedName), @unchecked Sendable {

      \(body)
      }
      """
        let doubleAccessorName = doubleName.lowercasingFirstCharacter
        let previewConfiguration = """
      #if DEBUG
      /// The shared `\(doubleName)` for SwiftUI preview dependency injection.
      /// - Important: Use this value only from SwiftUI previews.
      @inline(__always)
      \(access)nonisolated var \(doubleAccessorName): \(doubleName) {
        \(doubleName).preview
      }
      #else
      /// Preserves the accessor outside Debug builds, where no double exists to return.
      ///
      /// An injection site such as `.onPreview { \(doubleAccessorName) }` sits in production code and is compiled in
      /// every configuration, so the accessor must keep a type that resolves without the Debug-only double.
      /// - Warning: Available only in Debug builds.
      @inline(__always)
      \(access)nonisolated var \(doubleAccessorName): any \(qualifiedName) {
        preconditionFailure("\(doubleAccessorName) is unavailable outside Debug builds and SwiftUI previews")
      }
      #endif
      """
        return GeneratedDouble(
            declaration: generatedDeclaration,
            previewConfiguration: previewConfiguration
        )
    }
}
