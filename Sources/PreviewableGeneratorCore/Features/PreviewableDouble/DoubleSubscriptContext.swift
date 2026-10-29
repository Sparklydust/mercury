//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftParser
import SwiftSyntax

/// Preserves typed index arguments across getter, setter, and response-resolution generation.
struct DoubleSubscriptContext {

  let requirement: DoubleRequirement
  let access: String
  let isolated: Bool
  let sendable: Bool

  private var declaration: SubscriptDeclSyntax { requirement.subscriptDeclaration! }
  private var function: FunctionDeclSyntax { requirement.function! }
  private var parameters: [FunctionParameterSyntax] { Array(function.signature.parameterClause.parameters) }
  private var key: String { requirement.recordingKey ?? requirement.identity }
  private var resolutionName: String { "_previewableResolve_" + requirement.stubName }
  private var attributes: String {
    declaration.attributes.isEmpty ? "" : declaration.attributes.trimmedDescription + "\n"
  }
  private var nonisolated: String {
    declaration.modifiers.contains { $0.name.text == "nonisolated" } ? "nonisolated " : ""
  }
  private var dispatch: String { requirement.isStatic ? "static " : "" }
  private var generics: String { function.genericParameterClause?.trimmedDescription ?? "" }
  private var constraints: String { function.genericWhereClause.map { " " + $0.trimmedDescription } ?? "" }
  private var arguments: [String] {
    parameters.map { parameter -> String in
      let name = (parameter.secondName ?? parameter.firstName).text
      let label = parameter.firstName.text == "_" ? "" : parameter.firstName.text + ": "
      let isInout =
        parameter.type.as(AttributedTypeSyntax.self)?.specifiers.contains {
          $0.as(SimpleTypeSpecifierSyntax.self)?.specifier.text == "inout"
        } ?? false
      let autoclosure = parameter.type.trimmedDescription.contains("@autoclosure")
      return label + (isInout ? "&" : "") + name + (autoclosure ? "()" : "")
    }
  }

  /// Renders the getter with complete typed indices and a distinct read-recording key.
  /// - Parameter resolver: The resolver whose state allocates getter defaults.
  /// - Throws: `GenerationError` for unsupported getter requirements or unavailable defaults.
  func getter(resolver: inout DefaultValueResolver) throws -> GeneratedMethod {
    try PreviewableDoubleMemberBuilder.methodDeclaration(
      from: function,
      access: access,
      isolated: isolated,
      sendable: sendable,
      resolver: &resolver,
      stubName: requirement.stubName,
      recordingKey: key + ".get",
      responseExpression: "self.\(resolutionName)(\(arguments.joined(separator: ", ")))"
    )
  }

  private func responseResolution() -> String {
    var resolverFunction = function
    resolverFunction.signature.effectSpecifiers = nil
    let stub = "self.\(requirement.stubName)Stub"
    let response =
      function.genericParameterClause == nil
      ? stub
      : "\(stub).require((\(declaration.returnClause.type)).self, method: \(String(reflecting: key)))"
    let resolverSignature =
      "\(attributes)private \(nonisolated)\(dispatch)func \(resolutionName)\(generics)"
      + resolverFunction.signature.generatedDescription + constraints
    return """
      /// Resolves this accessor's response from its complete typed index arguments.
      \(resolverSignature) {
        \(response)
      }
      """
  }

  /// Renders the getter and any setter; writes record arguments without replacing the getter response.
  /// - Parameters:
  ///   - getter: The getter implementation with its captured response and recording.
  ///   - resolver: The resolver used to validate setter argument types.
  /// - Throws: `GenerationError` for unsupported setter requirements.
  func accessors(
    getter: GeneratedMethod,
    resolver: inout DefaultValueResolver
  ) throws -> [String] {
    let effects = function.signature.effectSpecifiers?.trimmedDescription ?? ""
    let getterEffects = effects.isEmpty ? "" : " " + effects
    var result = ["get\(getterEffects) \(getter.body)"]

    if requirement.isSettable {
      result.append(try setter(resolver: &resolver))
    }
    return result
  }

  private func setter(resolver: inout DefaultValueResolver) throws -> String {
    var setterFunction = function
    setterFunction.signature.returnClause = nil
    setterFunction.signature.effectSpecifiers = nil
    let names = Set(parameters.map { ($0.secondName ?? $0.firstName).text })
    var assignedName = "newValue"

    while names.contains(assignedName) {
      assignedName = "_" + assignedName
    }
    let valueParameter = Parser.parse(source: "func value(_ \(assignedName): \(declaration.returnClause.type)) {}")
      .statements.first!.item.as(FunctionDeclSyntax.self)!.signature.parameterClause.parameters.first!
    var setterParameters = parameters.map { $0.with(\.trailingComma, .commaToken(trailingTrivia: .space)) }
    setterParameters.append(valueParameter)
    setterFunction.signature.parameterClause.parameters = FunctionParameterListSyntax(setterParameters)
    let setter = try PreviewableDoubleMemberBuilder.methodDeclaration(
      from: setterFunction,
      access: access,
      isolated: isolated,
      sendable: sendable,
      resolver: &resolver,
      stubName: requirement.stubName,
      recordingKey: key + ".set"
    )
    return "set(\(assignedName)) \(setter.body)"
  }

  /// Renders the subscript witness and its typed response-resolution helper.
  /// - Parameters:
  ///   - stubs: Response, error, and observation storage for the subscript.
  ///   - accessors: The rendered getter and optional setter implementations.
  func render(
    stubs: [String],
    accessors: [String]
  ) -> GeneratedMethod {
    let resolution = responseResolution()
    let subscriptSignature =
      "\(attributes)\(access)\(nonisolated)\(dispatch)subscript\(generics)"
      + "\(declaration.parameterClause) \(declaration.returnClause)\(constraints)"
    let setterDocumentation =
      requirement.isSettable
      ? "/// Writes record indices and the assigned value without changing the getter response.\n" : ""
    return GeneratedMethod(
      stubs: stubs,
      requirement: """
        /// Returns the configured response for any index and records each accessor invocation.
        \(setterDocumentation)\(subscriptSignature) {
        \(accessors.joined(separator: "\n").indented(by: 2))
        }

        \(resolution)
        """
    )
  }

}
