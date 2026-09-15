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
      unconditional: [generated.previewConfiguration],
      globalNames: generated.globalNames
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
    guard !declaration.modifiers.isFileScoped else {
      throw GenerationError.message("@PreviewableDouble cannot access a private or fileprivate protocol")
    }
    let isolated = DoubleStorageBuilder.isIsolated(declaration, index: index)
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
      isolated: isolated)
    let rewriter = DoubleTypeSubstitution(associated.bindings)
    let members = originalMembers.filter { !$0.decl.is(AssociatedTypeDeclSyntax.self) }
      .map { rewriter.rewrite($0).cast(MemberBlockItemSyntax.self) }
    resolver.genericParameters = Set(associated.parameters)
    defer { resolver.genericParameters = [] }
    let requirements = try DoubleRequirement.collect(
      members, index: index,
      scope: qualifiedName.split(separator: ".").map(String.init),
      defaultIsolation: protocolIsolation(declaration, index: index))

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
    try validateNames(in: requirements, recordings: Set(recordings.keys))
    var stubDeclarations: [String] = []
    var staticStubs: [String] = []
    var requirementDeclarations: [String] = []
    var propertyNames: Set<String> = []
    var staticPropertyNames: Set<String> = []

    for requirement in requirements {
      let member = requirement.declaration
      if let variable = member.decl.as(VariableDeclSyntax.self) {
        var names = requirement.isStatic ? staticPropertyNames : propertyNames
        let properties = try PreviewableDoubleMemberBuilder.propertyDeclarations(
          from: variable,
          access: access,
          seen: &names,
          isolated: isolated,
          resolver: &resolver
        )
        if requirement.isStatic { staticPropertyNames = names } else { propertyNames = names }
        for property in properties {
          if requirement.isStatic { staticStubs.append(property.stub) } else { stubDeclarations.append(property.stub) }
          requirementDeclarations.append(property.requirement)
        }
        continue
      }
      if requirement.subscriptDeclaration != nil {
        let generated = try DoubleSubscriptBuilder.generate(
          requirement, access: access, isolated: isolated,
          resolver: &resolver)
        if requirement.isStatic { staticStubs += generated.stubs } else { stubDeclarations += generated.stubs }
        requirementDeclarations.append(generated.requirement)
        continue
      }
      if let function = requirement.function {
        let method = try PreviewableDoubleMemberBuilder.methodDeclaration(
          from: function,
          access: access,
          isolated: isolated,
          resolver: &resolver,
          stubName: requirement.stubName,
          recordingKey: requirement.recordingKey
        )
        if requirement.isStatic { staticStubs += method.stubs } else { stubDeclarations += method.stubs }
        requirementDeclarations.append(method.requirement)
        continue
      }
      if let initializer = member.decl.as(InitializerDeclSyntax.self) {
        if let requirement = try PreviewableDoubleMemberBuilder.initializerDeclaration(
          from: initializer, access: access, isolated: isolated, index: index)
        {
          requirementDeclarations.append(requirement)
        }
        continue
      }
    }

    var sections: [String] = ["nonisolated private let _previewableLock = NSRecursiveLock()"]
    if !associated.bindings.isEmpty { sections.append(associated.aliases(access: access)) }
    if requirements.contains(where: \.isStatic) {
      sections += DoubleStaticBuilder.declarations(
        stubs: staticStubs, recordings: recordings, access: access,
        isolation: protocolIsolation(declaration, index: index))
    }
    if !stubDeclarations.isEmpty {
      sections.append(
        (["// Mock values"] + stubDeclarations).joined(separator: "\n")
      )
    }
    sections.append(
      [
        "// Preview value",
        associated.parameters.isEmpty
          ? "/// The shared double used by previews."
          : "/// A fresh specialized double for each preview access.",
        "///",
        associated.parameters.isEmpty
          ? "/// Instantiated once; configured stubs and recorded calls persist between accesses."
          : "/// Configure associated responses without defaults before invoking their requirements.",
        "/// - Important: Use this value only from SwiftUI previews.",
        associated.parameters.isEmpty
          ? "\(access)nonisolated static let preview = \(doubleName)()"
          : "\(access)nonisolated static var preview: \(doubleName) { \(doubleName)() }",
      ].joined(separator: "\n")
    )
    sections.append("\(access)nonisolated init() {}")
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
    if !requirementDeclarations.isEmpty {
      sections.append(
        (["// Protocol requirements"] + requirementDeclarations)
          .joined(separator: "\n")
      )
    }

    let body = sections.map { $0.indented(by: 2) }.joined(separator: "\n\n")
    let classSignature =
      "\(access)final class \(doubleName)\(associated.genericClause): "
      + "\(qualifiedName), @unchecked Sendable\(associated.whereClause)"
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
      previewConfiguration: associated.parameters.isEmpty ? previewConfiguration : "",
      globalNames: [doubleName] + (associated.parameters.isEmpty ? [doubleAccessorName] : [])
    )
  }
  /// Rejects requirement names that collide with generated storage, stubs, or recording members.
  /// - Parameters:
  ///   - members: The flattened protocol requirements.
  ///   - recordings: Names reserved for actor-isolated argument dictionaries.
  /// - Throws: `GenerationError` when a requirement uses a reserved or generated name.
  private static func validateNames(in members: [DoubleRequirement], recordings: Set<String>) throws {
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
  private static func protocolIsolation(
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

}
