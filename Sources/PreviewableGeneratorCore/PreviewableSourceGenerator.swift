//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import Foundation
import SwiftParser
import SwiftSyntax

/// Generates derived Swift source for declarations annotated with Previewable macros.
public enum PreviewableSourceGenerator {

    /// Generates the doubles, fake factories, and preview accessors declared by the supplied source files.
    /// - Parameter files: The module's Swift source files, with the paths reported in diagnostics.
    /// - Returns: A compilable Swift source file containing the generated declarations.
    /// - Throws: `PreviewableDiagnostic` naming the declaration that must change.
    public static func generate(from files: [PreviewableSourceFile]) throws -> String {
        let trees = files.map { Parser.parse(source: $0.text) }
        let converters = zip(files, trees).map {
            SourceLocationConverter(fileName: $0.path, tree: $1)
        }

        var index = ModuleIndex()
        for (offset, tree) in trees.enumerated() {
            let collector = DeclarationCollector(fileIndex: offset)
            collector.walk(tree)
            index.merge(collector.index)
        }

        try validatePositions(in: index, files: files, converters: converters)
        try validateCollisions(in: index, files: files, converters: converters)

        var doubles: [String] = []
        var previewConfigurations: [String] = []
        var fakes: [String] = []
        var unavailableFakes: [String] = []
        var resolver = DefaultValueResolver(index: index, context: .double)
        var fakeResolver = DefaultValueResolver(index: index, context: .fake)

        for annotation in index.annotations {
            do {
                switch annotation.annotation {
                case .double:
                    guard let declaration = annotation.declaration.as(ProtocolDeclSyntax.self) else {
                        throw GenerationError.message(
                            "@PreviewableDouble can only be applied to a protocol"
                        )
                    }
                    let generated = try generateDouble(
                        from: declaration,
                        qualifiedName: annotation.qualifiedName,
                        index: index,
                        resolver: &resolver
                    )
                    doubles.append(generated.declaration)
                    previewConfigurations.append(generated.previewConfiguration)
                case .fake:
                    let generated = try generateFake(
                        from: annotation,
                        index: index,
                        resolver: &fakeResolver
                    )
                    fakes.append(generated.debug)
                    unavailableFakes.append(generated.release)
                }
            } catch let error as GenerationError {
                throw diagnostic(error.message, for: annotation, files: files, converters: converters)
            }
        }

        return assemble(
            imports: importedModules(in: trees, index: index),
            doubles: doubles,
            fakes: fakes,
            unavailableFakes: unavailableFakes,
            previewConfigurations: previewConfigurations
        )
    }

    /// Generates from raw source texts, without file paths.
    /// - Parameter sources: The complete Swift source texts to parse together.
    /// - Returns: A compilable Swift source file containing the generated declarations.
    /// - Throws: `PreviewableDiagnostic` naming the declaration that must change.
    public static func generate(from sources: [String]) throws -> String {
        try generate(
            from: sources.enumerated().map {
                PreviewableSourceFile(path: "<source \($0.offset)>", text: $0.element)
            }
        )
    }
}

// MARK: - Validation

private extension PreviewableSourceGenerator {

    static func validatePositions(
        in index: ModuleIndex,
        files: [PreviewableSourceFile],
        converters: [SourceLocationConverter]
    ) throws {
        for annotation in index.annotations {
            guard case .unsupported(let reason) = annotation.position else { continue }
            throw diagnostic(
                """
                @\(annotation.annotation.rawValue) cannot generate for '\(annotation.name)' declared \
                \(reason) — move the declaration to file scope or nest it directly in a type
                """,
                for: annotation,
                files: files,
                converters: converters
            )
        }
    }

    static func validateCollisions(
        in index: ModuleIndex,
        files: [PreviewableSourceFile],
        converters: [SourceLocationConverter]
    ) throws {
        var owners: [String: String] = [:]
        for annotation in index.annotations where annotation.annotation == .double {
            let doubleName = PreviewableNaming.doubleName(for: annotation.name)
            if let existing = owners[doubleName] {
                throw diagnostic(
                    """
                    '\(annotation.name)' and '\(existing)' both generate '\(doubleName)' \
                    — rename one of the protocols
                    """,
                    for: annotation,
                    files: files,
                    converters: converters
                )
            }
            owners[doubleName] = annotation.name
        }

        // An owned type carries one annotation at most, but an extension can be annotated in any number of files.
        var fakedTypes: Set<String> = []
        for annotation in index.annotations where annotation.annotation == .fake {
            guard !fakedTypes.insert(annotation.qualifiedName).inserted else { continue }
            throw diagnostic(
                """
                '\(annotation.qualifiedName)' is annotated with @PreviewableFake more than once \
                — keep a single annotation
                """,
                for: annotation,
                files: files,
                converters: converters
            )
        }
    }

    static func diagnostic(
        _ message: String,
        for annotation: AnnotatedDeclaration,
        files: [PreviewableSourceFile],
        converters: [SourceLocationConverter]
    ) -> PreviewableDiagnostic {
        let converter = converters[annotation.fileIndex]
        let location = converter.location(for: annotation.absolutePosition)
        return PreviewableDiagnostic(
            path: files[annotation.fileIndex].path,
            line: location.line,
            column: location.column,
            message: message
        )
    }
}

// MARK: - Assembly

private extension PreviewableSourceGenerator {

    static func importedModules(in trees: [SourceFileSyntax], index: ModuleIndex) -> [String] {
        let annotatedFiles = Set(index.annotations.map(\.fileIndex))
        var imports: Set<String> = []
        for (offset, tree) in trees.enumerated() where annotatedFiles.contains(offset) {
            for statement in tree.statements {
                guard let declaration = statement.item.as(ImportDeclSyntax.self) else { continue }
                imports.insert(declaration.path.trimmedDescription)
            }
        }
        imports.remove("SQMacrosKit")
        return imports.sorted()
    }

    static func assemble(
        imports: [String],
        doubles: [String],
        fakes: [String],
        unavailableFakes: [String],
        previewConfigurations: [String]
    ) -> String {
        let importSource = imports.map { "import \($0)" }.joined(separator: "\n")
        let doubleDeclarations = doubles.joined(separator: "\n\n")
        let fakeDeclarations = fakes.joined(separator: "\n\n")
        let unavailableFakeDeclarations = unavailableFakes.joined(separator: "\n\n")
        let previewDeclarations = previewConfigurations.joined(separator: "\n\n")
        return """
      //
      // Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
      //

      // Generated by SQMacrosKit PreviewableBuildToolPlugin. Do not edit.

      \(importSource)

      #if DEBUG
      \(doubleDeclarations)
      \(fakeDeclarations)
      #else
      \(unavailableFakeDeclarations)
      #endif

      \(previewDeclarations)
      """
    }
}

// MARK: - Doubles

private extension PreviewableSourceGenerator {

    struct GeneratedDouble {
        let declaration: String
        let previewConfiguration: String
    }

    struct GeneratedProperty {
        let stub: String
        let requirement: String
    }

    struct GeneratedMethod {
        let stubs: [String]
        let requirement: String
    }

    static func generateDouble(
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
        let doubleName = PreviewableNaming.doubleName(for: protocolName)
        let access = accessPrefix(from: declaration.modifiers)
        var visited: Set<String> = []
        let members = try flattenedRequirements(of: declaration, index: index, visited: &visited)

        var stubDeclarations: [String] = []
        var requirementDeclarations: [String] = []
        var methodSignatures: [String: String] = [:]
        var propertyNames: Set<String> = []

        for member in members {
            if let variable = member.decl.as(VariableDeclSyntax.self) {
                for property in try propertyDeclarations(
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
                let method = try methodDeclaration(
                    from: function,
                    access: access,
                    resolver: &resolver
                )
                stubDeclarations.append(contentsOf: method.stubs)
                requirementDeclarations.append(method.requirement)
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

        let body = sections.map { indent($0, by: 2) }.joined(separator: "\n\n")
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
      /// The shared `\(doubleName)` for SwiftUI preview dependency injection.
      /// - Important: Use this value only from SwiftUI previews.
      @inline(__always)
      \(access)nonisolated var \(doubleAccessorName): any \(qualifiedName) {
      #if DEBUG
        \(doubleName).preview
      #else
        preconditionFailure("\(doubleAccessorName) is unavailable outside Debug builds and SwiftUI previews")
      #endif
      }
      """
        return GeneratedDouble(
            declaration: generatedDeclaration,
            previewConfiguration: previewConfiguration
        )
    }

    /// Collects the protocol's own requirements followed by those of every base protocol declared in the module.
    static func flattenedRequirements(
        of declaration: ProtocolDeclSyntax,
        index: ModuleIndex,
        visited: inout Set<String>
    ) throws -> [MemberBlockItemSyntax] {
        guard visited.insert(declaration.name.text).inserted else { return [] }
        var members = Array(declaration.memberBlock.members)

        for inherited in declaration.inheritanceClause?.inheritedTypes ?? [] {
            let name = inherited.type.trimmedDescription
            if markerProtocols.contains(name) { continue }
            guard let base = index.protocols[name] ?? index.protocols[simpleName(of: name)] else {
                throw GenerationError.message(
                    """
                    @PreviewableDouble cannot read the requirements of '\(name)' \
                    — it is not declared in this module
                    """
                )
            }
            members.append(
                contentsOf: try flattenedRequirements(of: base, index: index, visited: &visited)
            )
        }
        return members
    }

    static func propertyDeclarations(
        from declaration: VariableDeclSyntax,
        access: String,
        seen: inout Set<String>,
        resolver: inout DefaultValueResolver
    ) throws -> [GeneratedProperty] {
        guard !isStatic(declaration.modifiers) else {
            throw GenerationError.message(
                "@PreviewableDouble does not support static property requirements"
            )
        }

        var properties: [GeneratedProperty] = []
        for binding in declaration.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                  let type = binding.typeAnnotation?.type,
                  let accessorBlock = binding.accessorBlock
            else {
                throw GenerationError.message(
                    "@PreviewableDouble requires named, explicitly typed protocol properties"
                )
            }

            let name = identifier.identifier.text
            guard seen.insert(name).inserted else { continue }
            let printedType = type.trimmedDescription
            let defaultValue = try resolver.defaultValue(for: type)
            let stub = "\(access)var \(name)Stub: \(printedType) = \(defaultValue)"

            if isSettable(accessorBlock) {
                properties.append(
                    GeneratedProperty(
                        stub: stub,
                        requirement: """
            \(access)var \(name): \(printedType) {
              get { \(name)Stub }
              set { \(name)Stub = newValue }
            }
            """
                    )
                )
            } else {
                properties.append(
                    GeneratedProperty(
                        stub: stub,
                        requirement: "\(access)var \(name): \(printedType) { \(name)Stub }"
                    )
                )
            }
        }
        return properties
    }

    static func methodDeclaration(
        from function: FunctionDeclSyntax,
        access: String,
        resolver: inout DefaultValueResolver
    ) throws -> GeneratedMethod {
        guard !isStatic(function.modifiers),
              function.genericParameterClause == .none,
              function.genericWhereClause == .none
        else {
            throw GenerationError.message(
                "@PreviewableDouble does not support static or generic method requirements"
            )
        }

        let methodName = function.name.text
        var declarations: [String] = []
        var parameters: [String] = []
        for parameter in function.signature.parameterClause.parameters {
            guard parameter.ellipsis == .none
            else { throw GenerationError.message("@PreviewableDouble does not support variadic parameters") }
            let localName = parameter.secondName?.text ?? parameter.firstName.text
            guard localName != "_" else { throw GenerationError.message("@PreviewableDouble requires a named local parameter") }
            // A non-escaping closure cannot be stored, so function-typed arguments are not recorded.
            guard !isFunctionType(parameter.type) else { continue }
            parameters.append(localName)
        }

        // `rethrows` may only throw from its own closure argument, so a stored error can never be replayed,
        // and a typed `throws(E)` requirement only accepts an `E`.
        let throwsClause = function.signature.effectSpecifiers?.throwsClause
        let isRethrowing = throwsClause?.throwsSpecifier.tokenKind == .keyword(.rethrows)
        let isThrowing = throwsClause != nil && !isRethrowing
        if isThrowing {
            let thrownType = throwsClause?.type?.trimmedDescription ?? "any Error"
            declarations.append("\(access)var \(methodName)ErrorStub: (\(thrownType))?")
        }

        let returnType = function.signature.returnClause?.type
        let returnsValue = returnType.map { !DefaultValueResolver.isVoid($0) } ?? false
        if let returnType, returnsValue {
            let defaultValue = try resolver.defaultValue(for: returnType)
            declarations.append(
                "\(access)var \(methodName)Stub: \(returnType.trimmedDescription) = \(defaultValue)"
            )
        }

        var body = [
            "calledMethods.append(#function)",
            "passedParameters[#function, default: []].append([\(parameters.joined(separator: ", "))])"
        ]
        if isThrowing {
            body.append("if let \(methodName)ErrorStub { throw \(methodName)ErrorStub }")
        }
        if returnsValue {
            body.append("return \(methodName)Stub")
        }
        let methodBody = body.map { "  \($0)" }.joined(separator: "\n")
        let signature = functionSignature(from: function)
        let requirement = """
      \(access)func \(methodName)\(signature) {
      \(methodBody)
      }
      """
        return GeneratedMethod(stubs: declarations, requirement: requirement)
    }

    static let markerProtocols: Set<String> = [
        "AnyObject", "Sendable", "AnyActor", "Actor", "Any"
    ]
}

// MARK: - Fakes

private extension PreviewableSourceGenerator {

    struct StoredProperty {
        let name: String
        let type: TypeSyntax
        let isMutable: Bool
    }

    struct GeneratedFake {
        let debug: String
        let release: String
    }

    static func generateFake(
        from annotation: AnnotatedDeclaration,
        index: ModuleIndex,
        resolver: inout DefaultValueResolver
    ) throws -> GeneratedFake {
        if let extended = annotation.declaration.as(ExtensionDeclSyntax.self) {
            return try generateExternalFake(from: annotation, in: extended, resolver: &resolver)
        }

        let members: MemberBlockItemListSyntax
        let access: String
        let isClass: Bool
        let genericClause: GenericParameterClauseSyntax?

        if let structure = annotation.declaration.as(StructDeclSyntax.self) {
            members = structure.memberBlock.members
            access = accessPrefix(from: structure.modifiers)
            genericClause = structure.genericParameterClause
            isClass = false
        } else if let classDeclaration = annotation.declaration.as(ClassDeclSyntax.self) {
            members = classDeclaration.memberBlock.members
            access = accessPrefix(from: classDeclaration.modifiers)
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
                — remove 'members:'
                """
            )
        }

        let genericParameters = Set(genericClause?.parameters.map(\.name.text) ?? [])
        let typeName = annotation.qualifiedName
        let genericSuffix = genericClause.map { clause in
            "<\(clause.parameters.map(\.name.text).joined(separator: ", "))>"
        } ?? String()
        let returnType = typeName + genericSuffix

        let properties = try eligibleStoredProperties(in: members)
        if isClass && properties.contains(where: { !$0.isMutable }) {
            throw GenerationError.message(
                "@PreviewableFake classes require mutable fake properties and an accessible init()"
            )
        }
        try validateInitializer(in: members, of: typeName, isClass: isClass, properties: properties)

        return try fakeFactory(
            typeName: typeName,
            returnType: returnType,
            access: access,
            properties: properties,
            genericParameters: genericParameters,
            declaresConvenienceInitializer: isClass && !properties.isEmpty,
            resolver: &resolver
        )
    }

    /// Generates a factory for a type this module extends but does not declare.
    ///
    /// Nothing about the extended type can be read, so the developer's `members:` list stands in for the stored
    /// properties an owned type exposes. A convenience initializer is never generated: the extended type already
    /// owns its initializers, and adding one from another module could not reach its stored properties anyway.
    static func generateExternalFake(
        from annotation: AnnotatedDeclaration,
        in declaration: ExtensionDeclSyntax,
        resolver: inout DefaultValueResolver
    ) throws -> GeneratedFake {
        let typeName = annotation.name
        guard declaration.genericWhereClause == nil else {
            throw GenerationError.message(
                """
                @PreviewableFake cannot generate for the constrained extension of '\(typeName)' \
                — remove the 'where' clause
                """
            )
        }
        guard !typeName.contains("<") else {
            throw GenerationError.message(
                """
                @PreviewableFake cannot generate for the generic type '\(typeName)' \
                — extend an unspecialised type
                """
            )
        }
        return try fakeFactory(
            typeName: typeName,
            returnType: typeName,
            access: accessPrefix(from: declaration.modifiers),
            properties: try declaredMembers(of: annotation),
            genericParameters: [],
            declaresConvenienceInitializer: false,
            resolver: &resolver
        )
    }

    /// Returns the members declared in the attribute for a type the generator cannot read.
    /// - Throws: `GenerationError` when `members:` is missing, malformed, empty or repeats a name.
    static func declaredMembers(of annotation: AnnotatedDeclaration) throws -> [StoredProperty] {
        guard case .argumentList(let arguments)? = annotation.attribute.arguments,
              let list = arguments.first(where: { $0.label?.text == "members" }),
              let elements = list.expression.as(ArrayExprSyntax.self)?.elements
        else {
            throw GenerationError.message(
                """
                @PreviewableFake cannot read '\(annotation.name)', declared outside this module \
                — list its initializer parameters in 'members:'
                """
            )
        }

        var properties: [StoredProperty] = []
        for element in elements {
            guard let member = declaredMember(from: element.expression) else {
                throw GenerationError.message(
                    """
                    @PreviewableFake expects every member of '\(annotation.name)' to read as \
                    ('name', Type.self)
                    """
                )
            }
            properties.append(member)
        }

        guard !properties.isEmpty else {
            throw GenerationError.message(
                """
                @PreviewableFake requires at least one member for '\(annotation.name)' \
                — list the values its initializer takes
                """
            )
        }
        guard Set(properties.map(\.name)).count == properties.count else {
            throw GenerationError.message(
                "@PreviewableFake requires distinct member names for '\(annotation.name)'"
            )
        }
        return properties
    }

    /// Reads one `("name", Type.self)` pair, or returns `nil` when the pair is not spelled that way.
    static func declaredMember(from expression: ExprSyntax) -> StoredProperty? {
        guard let pair = expression.as(TupleExprSyntax.self), pair.elements.count == 2,
              let literal = pair.elements.first?.expression.as(StringLiteralExprSyntax.self),
              let name = literal.representedLiteralValue, isIdentifier(name),
              let metatype = pair.elements.last?.expression.as(MemberAccessExprSyntax.self),
              metatype.declName.baseName.tokenKind == .keyword(.self),
              let base = metatype.base,
              let type = parsedType(base.trimmedDescription)
        else { return .none }
        return StoredProperty(name: name, type: type, isMutable: true)
    }

    /// Parses the base of a metatype expression back into the type syntax the default resolver works on.
    ///
    /// `String.self` reaches the generator as an expression, and the resolver matches on types: re-parsing the base
    /// inside a throwaway declaration is what bridges the two, and rejects a spelling that is not a type at all.
    static func parsedType(_ text: String) -> TypeSyntax? {
        let tree = Parser.parse(source: "var member: \(text)")
        guard !tree.hasError,
              let variable = tree.statements.first?.item.as(VariableDeclSyntax.self),
              let type = variable.bindings.first?.typeAnnotation?.type
        else { return .none }
        return type
    }

    static func isIdentifier(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first,
              CharacterSet.letters.contains(first) || first == "_"
        else { return false }
        return name.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_"
        }
    }

    /// Emits the Debug factory and its unavailable counterpart for an already-resolved member list.
    static func fakeFactory(
        typeName: String,
        returnType: String,
        access: String,
        properties: [StoredProperty],
        genericParameters: Set<String>,
        declaresConvenienceInitializer: Bool,
        resolver: inout DefaultValueResolver
    ) throws -> GeneratedFake {
        resolver.genericParameters = genericParameters
        var parameterDeclarations: [String] = []
        for property in properties {
            let printedType = property.type.trimmedDescription
            // A generic-typed property has no correct default, so the caller must supply it.
            if genericParameters.contains(printedType) {
                parameterDeclarations.append("\(property.name): \(printedType)")
                continue
            }
            let defaultValue = try resolver.defaultValue(for: property.type)
            parameterDeclarations.append("\(property.name): \(printedType) = \(defaultValue)")
        }
        resolver.genericParameters = []

        let parameters = parameterDeclarations.joined(separator: ",\n")
        let values = properties.enumerated().map { offset, property in
            let comma = offset == properties.count - 1 ? String() : ","
            return "  \(property.name): \(property.name)\(comma)"
        }
        let body = ([".init("] + values + [")"]).joined(separator: "\n")
        let dateDocumentation = properties.contains {
            $0.type.trimmedDescription == "Date"
        }
        ? """
        ///
        /// Generated `Date` values begin at `2024-01-01T00:00:00Z` and advance by one day in source order.
        """
        : String()

        let method = """
      /// Returns a fake `\(typeName)` with generated defaults or caller-provided stored-property values.
      \(dateDocumentation)
      \(access)static func fake(
      \(indent(parameters, by: 2))
      ) -> \(returnType) {
      \(indent(body, by: 2))
      }
      """
        var extensionMembers: [String] = []
        if declaresConvenienceInitializer {
            let initializerParameters = properties.map {
                "\($0.name): \($0.type.trimmedDescription)"
            }.joined(separator: ",\n")
            let assignments = properties.map {
                "self.\($0.name) = \($0.name)"
            }.joined(separator: "\n")
            extensionMembers.append(
        """
        \(access)convenience init(
        \(indent(initializerParameters, by: 2))
        ) {
          self.init()
        \(indent(assignments, by: 2))
        }
        """
            )
        }
        extensionMembers.append(method)
        let extensionBody = extensionMembers.map {
            indent($0, by: 2)
        }.joined(separator: "\n\n")
        let debug = """
      /// Provides a fake factory for Debug builds, test targets, and SwiftUI previews.
      extension \(typeName) {
      \(extensionBody)
      }
      """
        return GeneratedFake(
            debug: debug,
            release: unavailableFake(
                typeName: typeName,
                returnType: returnType,
                access: access,
                properties: properties,
                genericParameters: genericParameters
            )
        )
    }

    static func unavailableFake(
        typeName: String,
        returnType: String,
        access: String,
        properties: [StoredProperty],
        genericParameters: Set<String>
    ) -> String {
        let message = String(
            reflecting: "\(typeName).fake(...) is unavailable outside Debug builds and SwiftUI previews"
        )
        let parameters = properties.map { property in
            let printedType = property.type.trimmedDescription
            guard !genericParameters.contains(printedType) else {
                return "\(property.name): \(printedType)"
            }
            return "\(property.name): \(printedType) = { () -> \(printedType) in preconditionFailure(\(message)) }()"
        }.joined(separator: ",\n")
        return """
      /// Preserves the `fake(...)` signature outside Debug builds.
      extension \(typeName) {
        /// Prevents fake construction outside Debug builds.
        /// - Warning: Available only in Debug builds.
        @inline(__always)
        \(access)static func fake(
      \(indent(parameters, by: 4))
        ) -> \(returnType) {
          preconditionFailure(\(message))
        }
      }
      """
    }

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
        guard let uninitialized = firstPropertyWithoutInitialValue(in: members) else { return }
        throw GenerationError.message(
            """
            @PreviewableFake cannot construct '\(typeName)': '\(uninitialized)' has no initial value, so the \
            class has no 'init()' to call — give it a default value or declare a parameterless initializer
            """
        )
    }

    /// Returns whether an initializer can be called with the supplied property labels in order.
    static func accepts(_ initializer: InitializerDeclSyntax, properties: [StoredProperty]) -> Bool {
        guard !isFileScoped(initializer.modifiers), initializer.optionalMark == .none else { return false }
        let parameters = Array(initializer.signature.parameterClause.parameters)
        guard parameters.count >= properties.count else { return false }
        for (parameter, property) in zip(parameters, properties) where parameter.firstName.text != property.name {
            return false
        }
        return parameters.dropFirst(properties.count).allSatisfy { $0.defaultValue != .none }
    }

    /// Returns the first stored property that the compiler cannot give an implicit initial value.
    static func firstPropertyWithoutInitialValue(in members: MemberBlockItemListSyntax) -> String? {
        for member in members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !isStatic(variable.modifiers)
            else { continue }
            let isMutable = variable.bindingSpecifier.tokenKind == .keyword(.var)
            for binding in variable.bindings {
                guard binding.accessorBlock == .none,
                      binding.initializer == .none,
                      let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
                else { continue }
                // Only a mutable optional is implicitly `nil`.
                let isNilDefaulted = binding.typeAnnotation.map { isOptional($0.type) } ?? false
                guard !(isMutable && isNilDefaulted) else { continue }
                return identifier.identifier.text
            }
        }
        return .none
    }

    static func isOptional(_ type: TypeSyntax) -> Bool {
        type.is(OptionalTypeSyntax.self) || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
    }

    /// Returns the stored properties a fake factory can set.
    ///
    /// Private and file-private properties are deliberately excluded — reaching them would defeat the access
    /// control the developer asked for. They only block generation when they would also appear in the
    /// memberwise initializer, which the generated extension could then not call.
    static func eligibleStoredProperties(
        in members: MemberBlockItemListSyntax
    ) throws -> [StoredProperty] {
        var properties: [StoredProperty] = []
        for member in members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !isStatic(variable.modifiers)
            else { continue }

            let isHidden = isFileScoped(variable.modifiers)
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

    static func inferredType(from binding: PatternBindingSyntax) -> TypeSyntax? {
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

// MARK: - Syntax helpers

private extension PreviewableSourceGenerator {

    static func simpleName(of name: String) -> String {
        name.split(separator: ".").last.map(String.init) ?? name
    }

    static func accessPrefix(from modifiers: DeclModifierListSyntax) -> String {
        let accessLevels = ["open", "public", "package"]
        guard let modifier = modifiers.first(where: { accessLevels.contains($0.name.text) }) else {
            return String()
        }
        // `open` applies to neither the static factory nor the extension members generated here.
        return modifier.name.text == "open" ? "public " : "\(modifier.name.text) "
    }

    static func isStatic(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { ["class", "static"].contains($0.name.text) }
    }

    static func isFileScoped(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { ["private", "fileprivate"].contains($0.name.text) }
    }

    static func isSettable(_ accessorBlock: AccessorBlockSyntax) -> Bool {
        guard case .accessors(let accessors) = accessorBlock.accessors else { return false }
        return accessors.contains { $0.accessorSpecifier.tokenKind == .keyword(.set) }
    }

    static func isFunctionType(_ type: TypeSyntax) -> Bool {
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return isFunctionType(attributed.baseType)
        }
        return type.is(FunctionTypeSyntax.self)
    }

    static func indent(_ source: String, by spaces: Int) -> String {
        let prefix = String(repeating: " ", count: spaces)
        return source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? String() : prefix + $0 }
            .joined(separator: "\n")
    }

    static func functionSignature(from function: FunctionDeclSyntax) -> String {
        let parameters = function.signature.parameterClause.parameters.map { parameter in
            var parameter = parameter
            parameter.trailingComma = .none
            return parameter.trimmedDescription
        }
        let parameterClause: String
        if parameters.isEmpty {
            parameterClause = "()"
        } else if parameters.count == 1 {
            parameterClause = "(\(parameters[0]))"
        } else {
            parameterClause = "(\n  \(parameters.joined(separator: ",\n  "))\n)"
        }

        let effects = function.signature.effectSpecifiers.map {
            " \($0.trimmedDescription)"
        } ?? String()
        let returnClause = function.signature.returnClause.map {
            " \($0.trimmedDescription)"
        } ?? String()
        return parameterClause + effects + returnClause
    }
}
