//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Builds the stubs and requirement witnesses a generated double declares for each protocol member.
enum PreviewableDoubleMemberBuilder {

  /// Renders property stubs and witnesses, omitting names already encountered.
  /// - Parameters:
  ///   - declaration: The protocol property declaration.
  ///   - access: The access modifier prefix for generated members.
  ///   - seen: Property names already emitted; updated with new names.
  ///   - isolated: Whether stored values may rely on global-actor isolation.
  ///   - sendable: Whether unisolated stored values must conform to `Sendable`.
  ///   - resolver: The state used to construct property defaults.
  /// - Throws: `GenerationError` for unsupported properties or unavailable defaults.
  static func propertyDeclarations(
    from declaration: VariableDeclSyntax,
    access: String,
    seen: inout Set<String>,
    isolated: Bool,
    sendable: Bool,
    resolver: inout DefaultValueResolver
  ) throws -> [GeneratedProperty] {
    let isolation = DoubleStorageBuilder.isolationAttributes(in: declaration.attributes, index: resolver.index)
    let nonisolated = declaration.modifiers.contains { $0.name.text == "nonisolated" }
    let modifier = (nonisolated ? "nonisolated " : "") + (declaration.modifiers.isStatic ? "static " : "")
    let memberIsolated = !nonisolated && (isolated || !isolation.isEmpty)
    let attributes = declaration.attributes.isEmpty ? "" : declaration.attributes.trimmedDescription + "\n"
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
      resolver.fieldName = name
      let defaultValue = try configuredDefault(for: type, resolver: &resolver)
      let stub = DoubleStorageBuilder.property(
        name: name + "Stub", type: printedType, value: defaultValue, access: access,
        isolated: !sendable || memberIsolated, documentation: "The configured property value; assignments update this stub.",
        isolation: isolation, nonisolated: nonisolated
      )

      if accessorBlock.isSettable {
        properties.append(
          GeneratedProperty(
            stub: stub,
            requirement: """
              \(attributes)\(access)\(modifier)var \(name): \(printedType) {
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
            requirement: "\(attributes)\(access)\(modifier)var \(name): \(printedType) { \(name)Stub }"
          )
        )
      }
    }
    return properties
  }

  /// Renders a method witness with response stubs and synchronized invocation recording.
  ///
  /// Queued errors are consumed before the persistent error stub. Function arguments are excluded from records.
  /// Generic responses require configuration for the concrete return type.
  /// - Parameters:
  ///   - function: The protocol method requirement.
  ///   - access: The access modifier prefix for generated members.
  ///   - isolated: Whether recorded values may rely on global-actor isolation.
  ///   - sendable: Whether unisolated arguments and responses must conform to `Sendable`.
  ///   - resolver: The state used to construct nongeneric return defaults.
  ///   - stubName: The allocated storage stem, or `nil` to use the method name.
  ///   - recordingKey: The canonical overload identity, or `nil` to use Swift's function name.
  ///   - responseExpression: A typed subscript resolver call, when generating an accessor.
  /// - Throws: `GenerationError` for unsupported signatures or unavailable defaults.
  static func methodDeclaration(
    from function: FunctionDeclSyntax,
    access: String,
    isolated: Bool,
    sendable: Bool,
    resolver: inout DefaultValueResolver,
    stubName: String? = nil,
    recordingKey: String? = nil,
    responseExpression: String? = nil
  ) throws -> GeneratedMethod {
    let methodName = function.name.text
    let stub = stubName ?? methodName
    let receiver = function.modifiers.isStatic ? "_previewableStaticState" : "self"
    let key = recordingKey.map(String.init(reflecting:)) ?? "#function"
    let isolation = DoubleStorageBuilder.isolationAttributes(in: function.attributes, index: resolver.index)
    let nonisolated = function.modifiers.contains { $0.name.text == "nonisolated" }
    let modifier = (nonisolated ? "nonisolated " : "") + (function.modifiers.isStatic ? "static " : "")
    let memberIsolated = !nonisolated && (isolated || !isolation.isEmpty)
    let requiresSendable = sendable && !memberIsolated
    let isGeneric = function.genericParameterClause != nil
    resolver.fieldName = methodName
    let signatureTypes =
      function.signature.parameterClause.parameters.map(\.type)
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
      guard localName != "_" else {
        throw GenerationError.message("@PreviewableDouble requires a named local parameter")
      }
      // A non-escaping closure cannot be stored, so function-typed arguments are not recorded.
      guard try !resolver.resolvedType(parameter.type).isFunctionType else { continue }
      parameters.append(localName)
    }

    // `rethrows` may only throw from its own closure argument, so a stored error can never be replayed,
    // and a typed `throws(E)` requirement only accepts an `E`.
    let throwsClause = function.signature.effectSpecifiers?.throwsClause
    let isRethrowing = throwsClause?.throwsSpecifier.tokenKind == .keyword(.rethrows)
    let isThrowing = throwsClause != nil && !isRethrowing
    if isThrowing {
      let thrownType = throwsClause?.type?.trimmedDescription ?? "any Error"
      let genericNames = Set(function.genericParameterClause?.parameters.map(\.name.text) ?? [])
      if let type = throwsClause?.type, !genericNames.isDisjoint(with: type.writtenTypeNames) {
        throw GenerationError.message("@PreviewableDouble does not support a generic thrown error type")
      }
      declarations.append(
        DoubleStorageBuilder.property(
          name: stub + "ErrorStub", type: "(\(thrownType))?", value: ".none", access: access,
          isolated: !requiresSendable, documentation: "The persistent error thrown after queued errors are consumed.",
          isolation: isolation, nonisolated: nonisolated
        ))
      // A retrying caller needs a different outcome per call, which one stored error cannot express.
      declarations.append(
        DoubleStorageBuilder.property(
          name: stub + "ErrorsStub", type: "[\(thrownType)]", value: "[]", access: access,
          isolated: !requiresSendable,
          documentation: "Errors consumed atomically in FIFO order; concurrent callers are ordered by scheduling.",
          isolation: isolation, nonisolated: nonisolated
        ))
    }

    let returnType = function.signature.returnClause?.type
    let returnsValue = returnType.map { !DefaultValueResolver.isVoid($0) } ?? false
    if let returnType, returnsValue {
      if isGeneric {
        if requiresSendable { try GenericResponseValidator.validate(function, index: resolver.index) }
        let storage = requiresSendable ? "PreviewableResponses" : "PreviewableLocalResponses"
        declarations.append(
          """
          /// Responses keyed by concrete return type; configure each type before calling the requirement.
          \(isolation)\(access)\(nonisolated ? "nonisolated " : "")let \(stub)Stub = \(storage)()
          """)
      } else {
        let defaultValue = try configuredDefault(for: returnType, resolver: &resolver)
        declarations.append(
          DoubleStorageBuilder.property(
            name: stub + "Stub", type: returnType.trimmedDescription,
            value: defaultValue, access: access, isolated: !requiresSendable,
            documentation: defaultValue == nil
              ? "The response to configure before use. For optional responses, an explicit nil counts as configured."
              : "The response returned by this requirement after any configured errors are consumed.",
            isolation: isolation, nonisolated: nonisolated
          ))
      }
    }

    let recording = DoubleStorageBuilder.recordingName(for: isolation)
    var body = [
      "\(receiver)._previewable_calledMethods.append(\(key))",
      "\(receiver)._previewable_\(recording)[\(key), default: []].append([\(parameters.joined(separator: ", "))])",
    ]
    if requiresSendable {
      body.insert(contentsOf: parameters.map { "Mercury.previewableRequireSendable(\($0))" }, at: 0)
    }
    if isThrowing {
      // The queue is consumed first, so a test can fail the first calls and let a later one succeed.
      body.append("if !self.\(stub)ErrorsStub.isEmpty { throw self.\(stub)ErrorsStub.removeFirst() }")
      body.append("if let error = self.\(stub)ErrorStub { throw error }")
    }
    if returnsValue {
      if isGeneric, let returnType {
        let response = "self.\(stub)Stub.require((\(returnType.trimmedDescription)).self, method: \(key))"
        body.append("return " + (responseExpression ?? response))
      } else {
        body.append("return " + (responseExpression ?? "self.\(stub)Stub"))
      }
    }
    let effects = isThrowing ? " " + (throwsClause?.trimmedDescription ?? "throws") : ""
    let output = returnType?.trimmedDescription ?? "Void"
    let closureSignature = "()\(effects) -> \(output) in"
    let call =
      "\(returnsValue ? "return " : "")\(isThrowing ? "try " : "")"
      + "Mercury.previewableWithLock(\(receiver)._previewableLock) { \(closureSignature)"
    let methodBody = ([call] + body.map { "  " + $0 } + ["}"]).joined(separator: "\n").indented(by: 2)
    let signature = function.signature.generatedDescription
    let generics = function.genericParameterClause?.trimmedDescription ?? ""
    let constraints = function.genericWhereClause.map { " " + $0.trimmedDescription } ?? ""
    let attributes = function.attributes.isEmpty ? "" : function.attributes.trimmedDescription + "\n"
    let requirement = """
      \(attributes)\(access)\(modifier)func \(methodName)\(generics)\(signature)\(constraints) {
      \(methodBody)
      }
      """

    return GeneratedMethod(stubs: declarations, requirement: requirement)
  }

  /// Leaves associated-type responses unconfigured when no constructible default exists.
  /// - Parameters:
  ///   - type: The response's rewritten type.
  ///   - resolver: Default construction and the generated generic parameter names.
  /// - Throws: When an unsupported nongeneric type has no default.
  private static func configuredDefault(for type: TypeSyntax, resolver: inout DefaultValueResolver) throws -> String? {
    do { return try resolver.defaultValue(for: type) } catch let originalError {
      let canonicalizer = DoubleTypeCanonicalizer(
        index: resolver.index, scope: [],
        substitutions: Dictionary(uniqueKeysWithValues: resolver.genericParameters.map { ($0, $0) }))
      let resolved = try canonicalizer.resolved(type)
      do { return try resolver.defaultValue(for: resolved) } catch {
        guard !resolver.genericParameters.isDisjoint(with: resolved.writtenTypeNames) else { throw originalError }
        return nil
      }
    }
  }

  /// Returns the witness for an initializer requirement, or `nil` when the double's own `init()` already covers it.
  ///
  /// Generated witnesses record calls and non-function arguments. The shared parameterless initializer
  /// does not record calls.
  /// - Parameters:
  ///   - initializer: The initializer requirement to witness.
  ///   - access: The generated member's access modifier prefix.
  ///   - isolated: Whether recorded values may rely on global-actor isolation.
  ///   - sendable: Whether unisolated initializer arguments must conform to `Sendable`.
  ///   - index: Global actors available for resolving initializer isolation.
  /// - Throws: `GenerationError` when an argument has no local name for invocation recording.
  static func initializerDeclaration(
    from initializer: InitializerDeclSyntax,
    access: String,
    isolated: Bool,
    sendable: Bool,
    index: ModuleIndex
  ) throws -> String? {
    let parameters = Array(initializer.signature.parameterClause.parameters)
    // A synchronous, nonthrowing, nonfailable `init()` also witnesses weaker parameterless requirements.
    guard !parameters.isEmpty else { return .none }

    var recorded: [String] = []
    for parameter in parameters {
      let localName = (parameter.secondName ?? parameter.firstName).text
      guard localName != "_" else {
        throw GenerationError.message("@PreviewableDouble requires a named local parameter")
      }
      // A non-escaping closure cannot be stored, so function-typed arguments are not recorded.
      guard try !DoubleTypeCanonicalizer(index: index, scope: []).resolved(parameter.type).isFunctionType else { continue }
      recorded.append(localName)
    }

    let isolation = DoubleStorageBuilder.isolationAttributes(in: initializer.attributes, index: index)
    let nonisolated = initializer.modifiers.contains { $0.name.text == "nonisolated" }
    let modifier = nonisolated ? "nonisolated " : ""
    let checks =
      !sendable || (!nonisolated && (isolated || !isolation.isEmpty))
      ? "" : recorded.map { "Mercury.previewableRequireSendable(\($0))" }.joined(separator: "\n")
    let recording = DoubleStorageBuilder.recordingName(for: isolation)
    let attributes = initializer.attributes.isEmpty ? "" : initializer.attributes.trimmedDescription + "\n"
    let optionalMark = initializer.optionalMark?.text ?? String()
    return """
      \(attributes)\(access)\(modifier)init\(optionalMark)\(initializer.signature.generatedDescription) {
      \(checks.indented(by: 2))
        self._previewable_calledMethods.append(#function)
        self._previewable_\(recording)[#function, default: []].append([\(recorded.joined(separator: ", "))])
      }
      """
  }
}
