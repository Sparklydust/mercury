//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftParser
import SwiftSyntax

/// Renders subscript witnesses with distinct accessor recordings and typed response-resolution boundaries.
enum DoubleSubscriptBuilder {

  /// Renders a subscript, preserving every argument for future argument-based response policies.
  /// - Parameters:
  ///   - requirement: The canonical subscript requirement and allocated stub name.
  ///   - access: The double's effective access prefix.
  ///   - isolated: Whether the protocol has global-actor isolation.
  ///   - sendable: Whether unisolated indices and responses must conform to `Sendable`.
  ///   - resolver: The default construction context.
  /// - Throws: For unsupported argument forms or unavailable response defaults.
  static func generate(
    _ requirement: DoubleRequirement, access: String, isolated: Bool, sendable: Bool, resolver: inout DefaultValueResolver
  ) throws -> GeneratedMethod {
    let declaration = requirement.subscriptDeclaration!
    let function = requirement.function!
    let parameters = Array(function.signature.parameterClause.parameters)
    let arguments = parameters.map { parameter -> String in
      let name = (parameter.secondName ?? parameter.firstName).text
      let label = parameter.firstName.text == "_" ? "" : parameter.firstName.text + ": "
      let isInout =
        parameter.type.as(AttributedTypeSyntax.self)?.specifiers.contains {
          $0.as(SimpleTypeSpecifierSyntax.self)?.specifier.text == "inout"
        } ?? false
      let autoclosure = parameter.type.trimmedDescription.contains("@autoclosure")
      return label + (isInout ? "&" : "") + name + (autoclosure ? "()" : "")
    }
    let key = requirement.recordingKey ?? requirement.identity
    let resolutionName = "_previewableResolve_" + requirement.stubName
    let getter = try PreviewableDoubleMemberBuilder.methodDeclaration(
      from: function, access: access,
      isolated: isolated, sendable: sendable, resolver: &resolver, stubName: requirement.stubName, recordingKey: key + ".get",
      responseExpression: "self.\(resolutionName)(\(arguments.joined(separator: ", ")))")
    var resolverFunction = function
    resolverFunction.signature.effectSpecifiers = nil
    let stub = "self.\(requirement.stubName)Stub"
    let response =
      function.genericParameterClause == nil
      ? stub
      : "\(stub).require((\(declaration.returnClause.type)).self, method: \(String(reflecting: key)))"
    let attributes = declaration.attributes.isEmpty ? "" : declaration.attributes.trimmedDescription + "\n"
    let nonisolated = declaration.modifiers.contains { $0.name.text == "nonisolated" } ? "nonisolated " : ""
    let dispatch = requirement.isStatic ? "static " : ""
    let generics = function.genericParameterClause?.trimmedDescription ?? ""
    let constraints = function.genericWhereClause.map { " " + $0.trimmedDescription } ?? ""
    let resolverSignature =
      "\(attributes)private \(nonisolated)\(dispatch)func \(resolutionName)\(generics)"
      + resolverFunction.signature.generatedDescription + constraints
    let resolution = """
      /// Resolves this accessor's response from its complete typed index arguments.
      \(resolverSignature) {
        \(response)
      }
      """
    var getterEffects = function.signature.effectSpecifiers?.trimmedDescription ?? ""
    if !getterEffects.isEmpty { getterEffects = " " + getterEffects }
    var accessors = ["get\(getterEffects) \(body(of: getter.requirement))"]
    if requirement.isSettable {
      var setterFunction = function
      setterFunction.signature.returnClause = nil
      setterFunction.signature.effectSpecifiers = nil
      let names = Set(parameters.map { ($0.secondName ?? $0.firstName).text })
      var assignedName = "newValue"
      while names.contains(assignedName) { assignedName = "_" + assignedName }
      let valueParameter = Parser.parse(source: "func value(_ \(assignedName): \(declaration.returnClause.type)) {}")
        .statements.first!.item.as(FunctionDeclSyntax.self)!.signature.parameterClause.parameters.first!
      var setterParameters = parameters.map { $0.with(\.trailingComma, .commaToken(trailingTrivia: .space)) }
      setterParameters.append(valueParameter)
      setterFunction.signature.parameterClause.parameters = FunctionParameterListSyntax(setterParameters)
      let setter = try PreviewableDoubleMemberBuilder.methodDeclaration(
        from: setterFunction, access: access,
        isolated: isolated, sendable: sendable, resolver: &resolver, stubName: requirement.stubName, recordingKey: key + ".set")
      accessors.append("set(\(assignedName)) \(body(of: setter.requirement))")
    }
    let subscriptSignature =
      "\(attributes)\(access)\(nonisolated)\(dispatch)subscript\(generics)"
      + "\(declaration.parameterClause) \(declaration.returnClause)\(constraints)"
    let setterDocumentation =
      requirement.isSettable
      ? "/// Writes record indices and the assigned value without changing the getter response.\n" : ""
    return GeneratedMethod(
      stubs: getter.stubs,
      requirement: """
        /// Returns the configured response for any index and records each accessor invocation.
        \(setterDocumentation)\(subscriptSignature) {
        \(accessors.joined(separator: "\n").indented(by: 2))
        }

        \(resolution)
        """)
  }

  /// Extracts a rendered callable's body for use inside a subscript accessor.
  private static func body(of source: String) -> String {
    Parser.parse(source: source).statements.first!.item.as(FunctionDeclSyntax.self)!.body!.trimmedDescription
  }
}
