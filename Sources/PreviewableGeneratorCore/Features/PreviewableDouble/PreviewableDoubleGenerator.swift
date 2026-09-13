//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
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

  /// Validates protocol requirements and renders the double with its preview accessor.
  /// - Parameters:
  ///   - declaration: The annotated protocol.
  ///   - qualifiedName: The protocol name qualified by its enclosing types.
  ///   - index: Module declarations used for inheritance, isolation, and collision checks.
  ///   - resolver: The state used to construct stub defaults.
  /// - Throws: `GenerationError` for unsupported requirements, name conflicts, or unavailable defaults.
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

    guard !declaration.modifiers.isFileScoped else {
      throw GenerationError.message("@PreviewableDouble cannot access a private or fileprivate protocol")
    }
    let isolated = DoubleStorageBuilder.isIsolated(declaration, index: index)
    let protocolName = declaration.name.text
    let doubleName = PreviewableDoubleNaming.doubleName(for: protocolName)
    guard !index.declaresType(doubleName), index.protocols[doubleName] == nil else {
      throw GenerationError.message(
        "@PreviewableDouble generated type '\(doubleName)' conflicts with an existing declaration")
    }
    let access = declaration.modifiers.accessPrefix
    var visited: Set<String> = []
    let members = try PreviewableRequirementFlattener.requirements(of: declaration, index: index, visited: &visited)

    try validateNames(in: members)
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
          isolated: isolated,
          resolver: &resolver
        ) {
          stubDeclarations.append(property.stub)
          requirementDeclarations.append(property.requirement)
        }
        continue
      }
      if let function = member.decl.as(FunctionDeclSyntax.self) {
        let name = function.name.text
        let signature =
          (function.genericParameterClause?.trimmedDescription ?? "")
          + function.signature.trimmedDescription + (function.genericWhereClause?.trimmedDescription ?? "")
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
          isolated: isolated,
          resolver: &resolver
        )
        stubDeclarations.append(contentsOf: method.stubs)
        requirementDeclarations.append(method.requirement)
        continue
      }
      if let initializer = member.decl.as(InitializerDeclSyntax.self) {
        if let requirement = try PreviewableDoubleMemberBuilder.initializerDeclaration(
          from: initializer, access: access, isolated: isolated)
        {
          requirementDeclarations.append(requirement)
        }
        continue
      }
      if member.decl.is(AssociatedTypeDeclSyntax.self)
        || member.decl.is(SubscriptDeclSyntax.self)
      {
        throw GenerationError.message(
          "@PreviewableDouble does not support associated types or subscripts"
        )
      }
    }

    var sections: [String] = ["private let _previewableLock = NSRecursiveLock()"]
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
        "\(access)nonisolated static let preview = \(doubleName)()",
      ].joined(separator: "\n")
    )
    sections.append("\(access)nonisolated init() {}")
    sections.append(
      DoubleStorageBuilder.property(
        name: "calledMethods", type: "[String]", value: "[]", access: access + "private(set) ", isolated: true
      ))
    sections.append(
      DoubleStorageBuilder.property(
        name: "passedParameters", type: "[String: [[Any?]]]", value: "[:]", access: access + "private(set) ",
        isolated: true
      ))
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
  /// Rejects requirement names that collide with generated storage, stubs, or recording members.
  /// - Parameter members: The flattened protocol requirements.
  /// - Throws: `GenerationError` when a requirement uses a reserved or generated name.
  private static func validateNames(in members: [MemberBlockItemSyntax]) throws {
    let reserved: Set<String> = ["preview", "calledMethods", "passedParameters"]
    var generated = reserved
    var requirements: Set<String> = []
    var stubs: Set<String> = []
    for member in members {
      if let variable = member.decl.as(VariableDeclSyntax.self) {
        for binding in variable.bindings {
          guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
          let name = pattern.identifier.text
          requirements.insert(name)
          stubs.insert(name + "Stub")
        }
      } else if let function = member.decl.as(FunctionDeclSyntax.self) {
        let name = function.name.text
        requirements.insert(name)
        if let output = function.signature.returnClause?.type, !DefaultValueResolver.isVoid(output) {
          stubs.insert(name + "Stub")
        }
        if let clause = function.signature.effectSpecifiers?.throwsClause, clause.throwsSpecifier.text != "rethrows" {
          stubs.formUnion([name + "ErrorStub", name + "ErrorsStub"])
        }
      }
    }
    generated.formUnion(stubs)
    if let collision = requirements.sorted().first(where: { generated.contains($0) || $0.hasPrefix("_previewable") }) {
      throw GenerationError.message("@PreviewableDouble requirement '\(collision)' conflicts with a generated member")
    }
  }

}
