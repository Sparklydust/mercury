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
  ///   - resolver: The state used to construct property defaults.
  /// - Throws: `GenerationError` for unsupported properties or unavailable defaults.
  static func propertyDeclarations(
    from declaration: VariableDeclSyntax,
    access: String,
    seen: inout Set<String>,
    isolated: Bool,
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
      resolver.fieldName = name
      let defaultValue = try resolver.defaultValue(for: type)
      let stub = DoubleStorageBuilder.property(
        name: name + "Stub", type: printedType, value: defaultValue, access: access, isolated: isolated
      )

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

  /// Renders a method witness with response stubs and synchronized invocation recording.
  ///
  /// Queued errors are consumed before the persistent error stub. Function arguments are excluded from records.
  /// Generic responses require configuration for the concrete return type.
  /// - Parameters:
  ///   - function: The protocol method requirement.
  ///   - access: The access modifier prefix for generated members.
  ///   - isolated: Whether recorded values may rely on global-actor isolation.
  ///   - resolver: The state used to construct nongeneric return defaults.
  /// - Throws: `GenerationError` for unsupported signatures or unavailable defaults.
  static func methodDeclaration(
    from function: FunctionDeclSyntax,
    access: String,
    isolated: Bool,
    resolver: inout DefaultValueResolver
  ) throws -> GeneratedMethod {
    guard !function.modifiers.isStatic else {
      throw GenerationError.message(
        "@PreviewableDouble does not support static method requirements"
      )
    }

    let methodName = function.name.text
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
      let genericNames = Set(function.genericParameterClause?.parameters.map(\.name.text) ?? [])
      if let type = throwsClause?.type, !genericNames.isDisjoint(with: type.writtenTypeNames) {
        throw GenerationError.message("@PreviewableDouble does not support a generic thrown error type")
      }
      declarations.append(
        DoubleStorageBuilder.property(
          name: methodName + "ErrorStub", type: "(\(thrownType))?", value: ".none", access: access, isolated: isolated
        ))
      // A retrying caller needs a different outcome per call, which one stored error cannot express.
      declarations.append(
        DoubleStorageBuilder.property(
          name: methodName + "ErrorsStub", type: "[\(thrownType)]", value: "[]", access: access, isolated: isolated
        ))
    }

    let returnType = function.signature.returnClause?.type
    let returnsValue = returnType.map { !DefaultValueResolver.isVoid($0) } ?? false
    if let returnType, returnsValue {
      if isGeneric {
        declarations.append("\(access)let \(methodName)Stub = PreviewableResponses()")
      } else {
        declarations.append(
          DoubleStorageBuilder.property(
            name: methodName + "Stub", type: returnType.trimmedDescription,
            value: try resolver.defaultValue(for: returnType), access: access, isolated: isolated
          ))
      }
    }

    var body = [
      "self.calledMethods.append(#function)",
      "self.passedParameters[#function, default: []].append([\(parameters.joined(separator: ", "))])",
    ]
    if !isolated {
      body.insert(contentsOf: parameters.map { "Mercury.previewableRequireSendable(\($0))" }, at: 0)
    }
    if isThrowing {
      // The queue is consumed first, so a test can fail the first calls and let a later one succeed.
      body.append("if !self.\(methodName)ErrorsStub.isEmpty { throw self.\(methodName)ErrorsStub.removeFirst() }")
      body.append("if let \(methodName)ErrorStub = self.\(methodName)ErrorStub { throw \(methodName)ErrorStub }")
    }
    if returnsValue {
      if isGeneric, let returnType {
        body.append("return self.\(methodName)Stub.require((\(returnType.trimmedDescription)).self, method: #function)")
      } else {
        body.append("return self.\(methodName)Stub")
      }
    }
    let effects = isThrowing ? " " + (throwsClause?.trimmedDescription ?? "throws") : ""
    let output = returnType?.trimmedDescription ?? "Void"
    let closureSignature = "()\(effects) -> \(output) in"
    let call =
      "\(returnsValue ? "return " : "")\(isThrowing ? "try " : "")Mercury.previewableWithLock(self._previewableLock) { \(closureSignature)"
    let methodBody = ([call] + body.map { "  " + $0 } + ["}"]).joined(separator: "\n").indented(by: 2)
    let signature = function.signature.generatedDescription
    let generics = function.genericParameterClause?.trimmedDescription ?? ""
    let constraints = function.genericWhereClause.map { " " + $0.trimmedDescription } ?? ""
    let attributes = function.attributes.isEmpty ? "" : function.attributes.trimmedDescription + "\n"
    let requirement = """
      \(attributes)\(access)func \(methodName)\(generics)\(signature)\(constraints) {
      \(methodBody)
      }
      """

    return GeneratedMethod(stubs: declarations, requirement: requirement)
  }

  /// Returns the witness for an initializer requirement, or `nil` when the double's own `init()` already covers it.
  ///
  /// Generated witnesses record calls and non-function arguments. The shared parameterless initializer
  /// does not record calls.
  /// - Parameters:
  ///   - initializer: The initializer requirement to witness.
  ///   - access: The generated member's access modifier prefix.
  ///   - isolated: Whether recorded values may rely on global-actor isolation.
  /// - Throws: `GenerationError` when an argument has no local name for invocation recording.
  static func initializerDeclaration(
    from initializer: InitializerDeclSyntax,
    access: String,
    isolated: Bool
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

    let checks = isolated ? "" : recorded.map { "Mercury.previewableRequireSendable(\($0))" }.joined(separator: "\n")
    let optionalMark = initializer.optionalMark?.text ?? String()
    return """
      \(access)init\(optionalMark)\(initializer.signature.generatedDescription) {
      \(checks.indented(by: 2))
        self._previewable_calledMethods.append(#function)
        self._previewable_passedParameters[#function, default: []].append([\(recorded.joined(separator: ", "))])
      }
      """
  }
}
