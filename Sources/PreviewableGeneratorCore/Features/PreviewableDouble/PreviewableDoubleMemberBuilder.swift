//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Builds the stubs and requirement witnesses a generated double declares for each protocol member.
enum PreviewableDoubleMemberBuilder {

    static func propertyDeclarations(
        from declaration: VariableDeclSyntax,
        access: String,
        seen: inout Set<String>,
        resolver: inout DefaultValueResolver
    ) throws -> [GeneratedProperty] {
        guard !declaration.modifiers.isStatic else {
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
            guard !type.usesSelfType else {
                throw GenerationError.message(
                    "@PreviewableDouble does not support 'Self' in requirement '\(name)'"
                )
            }
            let printedType = type.trimmedDescription
            let defaultValue = try resolver.defaultValue(for: type)
            let stub = "\(access)var \(name)Stub: \(printedType) = \(defaultValue)"

            if accessorBlock.isSettable {
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
        guard !function.modifiers.isStatic,
              function.genericParameterClause == .none,
              function.genericWhereClause == .none
        else {
            throw GenerationError.message(
                "@PreviewableDouble does not support static or generic method requirements"
            )
        }

        let methodName = function.name.text
        let signatureTypes = function.signature.parameterClause.parameters.map(\.type)
            + [function.signature.returnClause?.type].compactMap { $0 }
        guard !signatureTypes.contains(where: \.usesSelfType) else {
            throw GenerationError.message(
                "@PreviewableDouble does not support 'Self' in requirement '\(methodName)'"
            )
        }
        var declarations: [String] = []
        var parameters: [String] = []
        for parameter in function.signature.parameterClause.parameters {
            guard parameter.ellipsis == .none
            else { throw GenerationError.message("@PreviewableDouble does not support variadic parameters") }
            let localName = parameter.secondName?.text ?? parameter.firstName.text
            guard localName != "_" else { throw GenerationError.message("@PreviewableDouble requires a named local parameter") }
            // A non-escaping closure cannot be stored, so function-typed arguments are not recorded.
            guard !parameter.type.isFunctionType else { continue }
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
            // A retrying caller needs a different outcome per call, which one stored error cannot express.
            declarations.append("\(access)var \(methodName)ErrorsStub: [\(thrownType)] = []")
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
            // The queue is consumed first, so a test can fail the first calls and let a later one succeed.
            body.append("if !\(methodName)ErrorsStub.isEmpty { throw \(methodName)ErrorsStub.removeFirst() }")
            body.append("if let \(methodName)ErrorStub { throw \(methodName)ErrorStub }")
        }
        if returnsValue {
            body.append("return \(methodName)Stub")
        }
        let methodBody = body.map { "  \($0)" }.joined(separator: "\n")
        let signature = function.signature.generatedDescription
        let requirement = """
      \(access)func \(methodName)\(signature) {
      \(methodBody)
      }
      """
        return GeneratedMethod(stubs: declarations, requirement: requirement)
    }

    /// Returns the witness for an initializer requirement, or `nil` when the double's own `init()` already covers it.
    ///
    /// A protocol may require an initializer, and a double that omits one simply does not conform — a failure that
    /// would surface as a conformance error in generated source rather than as a diagnostic. The witness records the
    /// call like every other requirement, so a factory protocol can be asserted on the same way.
    static func initializerDeclaration(
        from initializer: InitializerDeclSyntax,
        access: String
    ) throws -> String? {
        let parameters = Array(initializer.signature.parameterClause.parameters)
        let hasEffects = initializer.signature.effectSpecifiers != nil
        // The double already declares `init()`, which witnesses a parameterless requirement.
        guard !parameters.isEmpty || hasEffects || initializer.optionalMark != nil else { return .none }

        var recorded: [String] = []
        for parameter in parameters {
            let localName = (parameter.secondName ?? parameter.firstName).text
            guard localName != "_" else {
                throw GenerationError.message("@PreviewableDouble requires a named local parameter")
            }
            // A non-escaping closure cannot be stored, so function-typed arguments are not recorded.
            guard !parameter.type.isFunctionType else { continue }
            recorded.append(localName)
        }

        let optionalMark = initializer.optionalMark?.text ?? String()
        return """
      \(access)init\(optionalMark)\(initializer.signature.generatedDescription) {
        calledMethods.append(#function)
        passedParameters[#function, default: []].append([\(recorded.joined(separator: ", "))])
      }
      """
    }
}
