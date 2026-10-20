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
    let context = DoublePropertyContext(
      declaration: declaration,
      access: access,
      isolated: isolated,
      sendable: sendable,
      isolation: DoubleStorageBuilder.isolationAttributes(in: declaration.attributes, index: resolver.index)
    )
    var properties: [GeneratedProperty] = []

    for binding in declaration.bindings {
      guard let property = try context.property(from: binding, seen: &seen, resolver: &resolver) else { continue }
      properties.append(property)
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
    let context = DoubleMethodContext(
      function: function,
      access: access,
      isolated: isolated,
      sendable: sendable,
      stub: stubName ?? function.name.text,
      key: recordingKey.map(String.init(reflecting:)) ?? "#function",
      responseExpression: responseExpression,
      isolation: DoubleStorageBuilder.isolationAttributes(in: function.attributes, index: resolver.index)
    )
    resolver.fieldName = context.methodName
    try context.validateSignature()
    let parameters = try context.recordedParameters(resolver: &resolver)
    let declarations = try context.stubDeclarations(resolver: &resolver)

    return GeneratedMethod(stubs: declarations, requirement: context.requirement(parameters: parameters))
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
      guard try !DoubleTypeCanonicalizer(index: index, scope: []).resolved(parameter.type).isFunctionType else {
        continue
      }
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
