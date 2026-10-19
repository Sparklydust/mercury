//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Builds a validated double and its preview accessor.
enum PreviewableDoubleRenderer {

  /// Validates protocol requirements and renders the double with its preview accessor.
  /// - Parameters:
  ///   - declaration: The annotated protocol.
  ///   - qualifiedName: The protocol name qualified by its enclosing types.
  ///   - index: Module declarations used for inheritance, isolation, and collision checks.
  ///   - resolver: The state used to construct stub defaults.
  /// - Throws: `GenerationError` for unsupported requirements, name conflicts, or unavailable defaults.
  static func generate(
    from declaration: ProtocolDeclSyntax,
    qualifiedName: String,
    index: ModuleIndex,
    resolver: inout DefaultValueResolver
  ) throws -> GeneratedDouble {
    guard !declaration.modifiers.isFileScoped else {
      throw GenerationError.message("@PreviewableDouble cannot access a private or fileprivate protocol")
    }
    let isolated = DoubleStorageBuilder.isIsolated(declaration, index: index)
    let sendable = isolated || GenericResponseValidator.impliesSendable(
      TypeSyntax(IdentifierTypeSyntax(name: .identifier(qualifiedName))), index: index)
    let protocolName = declaration.name.text
    let doubleName = PreviewableDoubleNaming.doubleName(for: protocolName)
    guard index.typeAccess[doubleName] == nil else {
      throw GenerationError.message(
        "@PreviewableDouble generated type '\(doubleName)' conflicts with an existing declaration")
    }
    let access = index.accessPrefix(for: qualifiedName)
    var visited: Set<String> = []
    let originalMembers = try PreviewableRequirementFlattener.requirements(
      of: declaration, index: index, visited: &visited)
    let associated = try DoubleAssociatedTypes(
      declaration: declaration, members: originalMembers, index: index,
      isolated: isolated, sendable: sendable)
    let rewriter = DoubleTypeSubstitution(associated.bindings)
    let members = originalMembers.filter { !$0.decl.is(AssociatedTypeDeclSyntax.self) }
      .map { rewriter.rewrite($0).cast(MemberBlockItemSyntax.self) }
    resolver.genericParameters = Set(associated.parameters)
    defer { resolver.genericParameters = [] }
    let requirements = try DoubleRequirement.collect(
      members, index: index,
      scope: qualifiedName.split(separator: ".").map(String.init),
      defaultIsolation: protocolIsolation(declaration, index: index))

    let recordings = try actorRecordings(in: members, index: index)
    try validateNames(in: requirements, recordings: Set(recordings.keys))
    let generated = try PreviewableDoubleRequirementsBuilder.generate(
      requirements: requirements, access: access, isolated: isolated, sendable: sendable,
      index: index, resolver: &resolver)
    return render(
      declaration: declaration, qualifiedName: qualifiedName, index: index, associated: associated,
      requirements: requirements, recordings: recordings, generated: generated, sendable: sendable)
  }
}

private extension PreviewableDoubleRenderer {

  static func actorRecordings(in members: [MemberBlockItemSyntax], index: ModuleIndex) throws -> [String: String] {
    var recordings: [String: String] = [:]
    for member in members {
      let attributes =
        member.decl.as(FunctionDeclSyntax.self)?.attributes
        ?? member.decl.as(InitializerDeclSyntax.self)?.attributes
        ?? member.decl.as(SubscriptDeclSyntax.self)?.attributes
        ?? member.decl.as(VariableDeclSyntax.self)?.attributes
      guard let attributes else { continue }
      let isolation = DoubleStorageBuilder.isolationAttributes(in: attributes, index: index)
      guard !isolation.isEmpty else { continue }
      let name = DoubleStorageBuilder.recordingName(for: isolation)
      if let existing = recordings[name], existing != isolation {
        throw GenerationError.message("@PreviewableDouble actor recording '\(name)' conflicts with another actor")
      }
      recordings[name] = isolation
    }
    return recordings
  }

  static func render(
    declaration: ProtocolDeclSyntax, qualifiedName: String, index: ModuleIndex, associated: DoubleAssociatedTypes,
    requirements: [DoubleRequirement], recordings: [String: String],
    generated: GeneratedDoubleRequirements, sendable: Bool
  ) -> GeneratedDouble {
    let protocolName = declaration.name.text
    let doubleName = PreviewableDoubleNaming.doubleName(for: protocolName)
    let access = index.accessPrefix(for: qualifiedName)
    var sections: [String] = ["nonisolated private let _previewableLock = NSRecursiveLock()"]
    if !associated.bindings.isEmpty { sections.append(associated.aliases(access: access)) }
    if requirements.contains(where: \.isStatic) {
      sections += DoubleStaticBuilder.declarations(
        stubs: generated.staticStubs, recordings: recordings, access: access,
        isolation: protocolIsolation(declaration, index: index))
    }
    if !generated.stubs.isEmpty {
      sections.append(
        (["// Mock values"] + generated.stubs).joined(separator: "\n")
      )
    }
    let sharedPreview = sendable && associated.parameters.isEmpty
    sections.append(previewDeclaration(access: access, doubleName: doubleName, shared: sharedPreview))
    sections.append("\(access)nonisolated init() {}")
    sections += recordingDeclarations(access: access, recordings: recordings)
    if !generated.declarations.isEmpty {
      sections.append(
        (["// Protocol requirements"] + generated.declarations)
          .joined(separator: "\n")
      )
    }

    let body = sections.map { $0.indented(by: 2) }.joined(separator: "\n\n")
    let classSignature =
      "\(access)final class \(doubleName)\(associated.genericClause): "
      + "\(qualifiedName)\(sendable ? ", @unchecked Sendable" : "")\(associated.whereClause)"
    let generatedDeclaration = """
      /// A test double for `\(protocolName)`.
      ///
      /// Configure stubs and inspect recorded calls when testing protocol consumers.
      /// - Important: Available only in Debug builds.
      \(classSignature) {

      \(body)
      }
      """
    let doubleAccessorName = doubleName.lowercasingFirstCharacter
    let previewConfiguration = previewAccessor(
      access: access, doubleName: doubleName, qualifiedName: qualifiedName, shared: sharedPreview)
    return GeneratedDouble(
      declaration: generatedDeclaration,
      previewConfiguration: associated.parameters.isEmpty ? previewConfiguration : "",
      globalNames: [doubleName] + (associated.parameters.isEmpty ? [doubleAccessorName] : [])
    )
  }

  /// Rejects requirement names that collide with generated storage, stubs, or recording members.
  /// - Parameters:
  ///   - members: The flattened protocol requirements.
  ///   - recordings: Names reserved for actor-isolated argument dictionaries.
  /// - Throws: `GenerationError` when a requirement uses a reserved or generated name.
  static func validateNames(in members: [DoubleRequirement], recordings: Set<String>) throws {
    let reserved: Set<String> = Set(["preview", "calledMethods", "passedParameters", "withStaticStubs"]).union(
      recordings)
    var generated = reserved
    var requirements: Set<String> = []
    var stubs: Set<String> = []
    for requirement in members {
      let member = requirement.declaration
      if let variable = member.decl.as(VariableDeclSyntax.self) {
        for binding in variable.bindings {
          guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
          let name = pattern.identifier.text
          requirements.insert(name)
          stubs.insert(name + "Stub")
        }
      } else if let function = requirement.function {
        let name = requirement.name
        requirements.insert(name)
        if let output = function.signature.returnClause?.type, !DefaultValueResolver.isVoid(output) {
          stubs.insert(requirement.stubName + "Stub")
        }
        if let clause = function.signature.effectSpecifiers?.throwsClause, clause.throwsSpecifier.text != "rethrows" {
          stubs.formUnion([requirement.stubName + "ErrorStub", requirement.stubName + "ErrorsStub"])
        }
      }
    }
    generated.formUnion(stubs)
    if let collision = stubs.intersection(recordings).sorted().first {
      throw GenerationError.message("@PreviewableDouble stub '\(collision)' conflicts with an actor recording")
    }
    if let collision = requirements.sorted().first(where: { generated.contains($0) || $0.hasPrefix("_previewable") }) {
      throw GenerationError.message("@PreviewableDouble requirement '\(collision)' conflicts with a generated member")
    }
  }

  /// Finds the protocol's declared or inherited global actor for its scoped static state.
  static func protocolIsolation(
    _ declaration: ProtocolDeclSyntax, index: ModuleIndex, visited: Set<String> = []
  ) -> String {
    let name = index.protocols.first { $0.value.id == declaration.id }?.key ?? declaration.name.text
    guard !visited.contains(name) else { return "" }
    let scope = name.split(separator: ".").map(String.init)
    let own = DoubleStorageBuilder.isolationAttributes(in: declaration.attributes, index: index, scope: scope)
    if !own.isEmpty { return own }
    for inherited in declaration.inheritanceClause?.inheritedTypes ?? [] {
      if let key = index.resolve(inherited.type.trimmedDescription, scope: scope), let base = index.protocols[key] {
        let isolation = protocolIsolation(base, index: index, visited: visited.union([name]))
        if !isolation.isEmpty { return isolation }
      }
    }
    return ""
  }

  static func previewDeclaration(access: String, doubleName: String, shared: Bool) -> String {
    return (
      [
        "// Preview value",
        shared
          ? "/// The shared double used by previews."
          : "/// A fresh double for each preview access.",
        "///",
        shared
          ? "/// Instantiated once; configured stubs and recorded calls persist between accesses."
          : "/// Keep the returned instance to retain configured stubs and recorded calls.",
        "/// - Important: Use this value only from SwiftUI previews.",
        shared
          ? "\(access)nonisolated static let preview = \(doubleName)()"
          : "\(access)nonisolated static var preview: \(doubleName) { \(doubleName)() }",
      ].joined(separator: "\n")
    )
  }

  static func recordingDeclarations(access: String, recordings: [String: String]) -> [String] {
    var sections: [String] = []
    sections.append(
      [
        "// Spy values",
        DoubleStorageBuilder.property(
          name: "calledMethods", type: "[String]", value: "[]", access: access + "private(set) ", isolated: true,
          documentation: "The protocol method names invoked on this double.", nonisolated: true
        ),
        DoubleStorageBuilder.property(
          name: "passedParameters", type: "[String: [[Any?]]]", value: "[:]", access: access + "private(set) ",
          isolated: true,
          documentation: "The arguments recorded in the protocol's isolation, grouped by method.",
          sharedBacking: true
        ),
      ].joined(separator: "\n")
    )
    for name in recordings.keys.sorted() {
      sections.append(
        DoubleStorageBuilder.property(
          name: name, type: "[String: [[Any?]]]", value: "[:]", access: access + "private(set) ", isolated: true,
          documentation: "The arguments recorded by requirements isolated to this actor, grouped by method.",
          isolation: recordings[name] ?? ""
        )
      )
    }
    return sections
  }

  static func previewAccessor(access: String, doubleName: String, qualifiedName: String, shared: Bool) -> String {
    let doubleAccessorName = doubleName.lowercasingFirstCharacter
    return """
      #if DEBUG
      /// \(shared ? "The shared" : "A fresh") `\(doubleName)` for SwiftUI preview dependency injection.
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
  }

}
