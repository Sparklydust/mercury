//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Renders one method's storage and invocation while preserving its isolation and error contract.
struct DoubleMethodContext {

  let function: FunctionDeclSyntax
  let access: String
  let isolated: Bool
  let sendable: Bool
  let stub: String
  let key: String
  let responseExpression: String?
  let isolation: String

  var methodName: String { function.name.text }
  private var receiver: String { function.modifiers.isStatic ? "_previewableStaticState" : "self" }
  private var nonisolated: Bool { function.modifiers.contains { $0.name.text == "nonisolated" } }
  private var modifier: String {
    (nonisolated ? "nonisolated " : "") + (function.modifiers.isStatic ? "static " : "")
  }
  private var memberIsolated: Bool { !nonisolated && (isolated || !isolation.isEmpty) }
  private var requiresSendable: Bool { sendable && !memberIsolated }
  private var isGeneric: Bool { function.genericParameterClause != nil }
  private var throwsClause: ThrowsClauseSyntax? { function.signature.effectSpecifiers?.throwsClause }
  // A rethrows witness can only forward errors from its own closure argument.
  private var isThrowing: Bool {
    throwsClause != nil && throwsClause?.throwsSpecifier.tokenKind != .keyword(.rethrows)
  }
  private var returnType: TypeSyntax? { function.signature.returnClause?.type }
  private var returnsValue: Bool { returnType.map { !DefaultValueResolver.isVoid($0) } ?? false }

  func validateSignature() throws {
    let signatureTypes =
    function.signature.parameterClause.parameters.map(\.type)
    + [function.signature.returnClause?.type].compactMap { $0 }
    guard !signatureTypes.contains(where: \.usesSelfType) else {
      throw GenerationError.message(
        "@PreviewableDouble does not support 'Self' in requirement '\(methodName)'"
      )
    }
  }

  func recordedParameters(resolver: inout DefaultValueResolver) throws -> [String] {
    var parameters: [String] = []

    for parameter in function.signature.parameterClause.parameters {
      guard parameter.ellipsis == .none
      else { throw GenerationError.message("@PreviewableDouble does not support variadic parameters") }

      let localName = parameter.secondName?.text ?? parameter.firstName.text

      guard localName != "_"
      else { throw GenerationError.message("@PreviewableDouble requires a named local parameter") }

      // A non-escaping closure cannot be stored, so function-typed arguments are not recorded.
      guard try !resolver.resolvedType(parameter.type).isFunctionType else { continue }
      parameters.append(localName)
    }
    return parameters
  }

  func stubDeclarations(
    resolver: inout DefaultValueResolver
  ) throws -> [String] {
    try errorDeclarations() + responseDeclarations(resolver: &resolver)
  }

  private func errorDeclarations() throws -> [String] {
    guard isThrowing else { return [] }

    let thrownType = throwsClause?.type?.trimmedDescription ?? "any Error"
    let genericNames = Set(function.genericParameterClause?.parameters.map(\.name.text) ?? [])

    if let type = throwsClause?.type, !genericNames.isDisjoint(with: type.writtenTypeNames) {
      throw GenerationError.message("@PreviewableDouble does not support a generic thrown error type")
    }

    return [
      errorStorage(
        suffix: "ErrorStub",
        type: "(\(thrownType))?",
        value: ".none",
        documentation: "The persistent error thrown after queued errors are consumed."
      ),
      errorStorage(
        suffix: "ErrorsStub",
        type: "[\(thrownType)]",
        value: "[]",
        documentation: "Errors consumed atomically in FIFO order; concurrent callers are ordered by scheduling."
      )
    ]
  }

  private func errorStorage(
    suffix: String,
    type: String,
    value: String,
    documentation: String
  ) -> String {
    DoubleStorageBuilder.property(
      name: stub + suffix,
      type: type,
      value: value,
      access: access,
      isolated: !requiresSendable,
      documentation: documentation,
      isolation: isolation,
      nonisolated: nonisolated
    )
  }

  private func responseDeclarations(resolver: inout DefaultValueResolver) throws -> [String] {
    var declarations: [String] = []

    if let returnType, returnsValue {
      if isGeneric {
        if requiresSendable {
          try GenericResponseValidator.validate(function, index: resolver.index)
        }
        let storage = requiresSendable ? "PreviewableResponses" : "PreviewableLocalResponses"
        declarations.append(
          """
          /// Responses keyed by concrete return type; configure each type before calling the requirement.
          \(isolation)\(access)\(nonisolated ? "nonisolated " : "")let \(stub)Stub: \(storage) = \(storage)()
          """
        )
      } else {
        let defaultValue = try DoubleResponseDefaultResolver.resolve(for: returnType, resolver: &resolver)
        declarations.append(
          DoubleStorageBuilder.property(
            name: stub + "Stub",
            type: returnType.trimmedDescription,
            value: defaultValue,
            access: access,
            isolated: !requiresSendable,
            documentation: defaultValue == nil
            ? "The response to configure before use. For optional responses, an explicit nil counts as configured."
            : "The response returned by this requirement after any configured errors are consumed.",
            isolation: isolation,
            nonisolated: nonisolated
          )
        )
      }
    }
    return declarations
  }

  private func invocationBody(parameters: [String]) -> [String] {
    let recording = DoubleStorageBuilder.recordingName(for: isolation)
    var body = [
      "\(receiver)._previewable_calledMethods.append(\(key))",
      "\(receiver)._previewable_\(recording)[\(key), default: []].append([\(parameters.joined(separator: ", "))])"
    ]
    if requiresSendable {
      body.insert(contentsOf: parameters.map { "Mercury.previewableRequireSendable(\($0))" }, at: .zero)
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
    return body
  }

  func requirement(parameters: [String]) -> String {
    let body = invocationBody(parameters: parameters)
    let effects = isThrowing ? " " + (throwsClause?.trimmedDescription ?? "throws") : ""
    let output = returnType?.trimmedDescription ?? "Void"
    let closureSignature = "()\(effects) -> \(output) in"
    let call = "\(returnsValue ? "return " : "")\(isThrowing ? "try " : "")"
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

    return requirement
  }
}
