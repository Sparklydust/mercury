//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

/// Renders requirement implementations and their instance and static stubs.
struct PreviewableDoubleRequirementsBuilder {

  private let access: String
  private let isolated: Bool
  private let sendable: Bool
  private let index: ModuleIndex
  private var result = GeneratedDoubleRequirements()
  private var propertyNames: Set<String> = []
  private var staticPropertyNames: Set<String> = []

  /// Renders validated requirements while keeping instance and scoped static storage separate.
  /// - Parameters:
  ///   - requirements: Canonical requirements in emission order.
  ///   - access: The generated double's effective access prefix.
  ///   - isolated: Whether the protocol is globally actor-isolated.
  ///   - sendable: Whether instances must support transfer between isolation domains.
  ///   - index: Module declarations used for requirement validation.
  ///   - resolver: The resolver whose state allocates distinct response defaults.
  /// - Throws: `GenerationError` for unsupported requirements or unavailable defaults.
  static func generate(
    requirements: [DoubleRequirement],
    access: String,
    isolated: Bool,
    sendable: Bool,
    index: ModuleIndex,
    resolver: inout DefaultValueResolver
  ) throws -> GeneratedDoubleRequirements {
    var builder = Self(access: access, isolated: isolated, sendable: sendable, index: index)

    for requirement in requirements {
      try builder.append(requirement, resolver: &resolver)
    }

    return builder.result
  }
}

private extension PreviewableDoubleRequirementsBuilder {

  mutating func append(
    _ requirement: DoubleRequirement,
    resolver: inout DefaultValueResolver
  ) throws {
    let member = requirement.declaration

    if let variable = member.decl.as(VariableDeclSyntax.self) {
      try appendProperties(from: variable, isStatic: requirement.isStatic, resolver: &resolver)
    } else if requirement.subscriptDeclaration != nil {
      let generated = try DoubleSubscriptBuilder.generate(
        requirement,
        access: access,
        isolated: isolated,
        sendable: sendable || requirement.isStatic,
        resolver: &resolver
      )
      append(stubs: generated.stubs, declaration: generated.requirement, isStatic: requirement.isStatic)
    } else if let function = requirement.function {
      let method = try PreviewableDoubleMemberBuilder.methodDeclaration(
        from: function,
        access: access,
        isolated: isolated,
        sendable: sendable || requirement.isStatic,
        resolver: &resolver,
        stubName: requirement.stubName,
        recordingKey: requirement.recordingKey
      )
      append(stubs: method.stubs, declaration: method.requirement, isStatic: requirement.isStatic)
    } else if let initializer = member.decl.as(InitializerDeclSyntax.self) {
      try appendInitializer(from: initializer)
    }
  }

  mutating func appendProperties(
    from variable: VariableDeclSyntax,
    isStatic: Bool,
    resolver: inout DefaultValueResolver
  ) throws {
    var names = isStatic ? staticPropertyNames : propertyNames
    let properties = try PreviewableDoubleMemberBuilder.propertyDeclarations(
      from: variable,
      access: access,
      seen: &names,
      isolated: isolated,
      sendable: sendable || isStatic,
      resolver: &resolver
    )
    if isStatic { staticPropertyNames = names } else { propertyNames = names }
    for property in properties {
      append(stubs: [property.stub], declaration: property.requirement, isStatic: isStatic)
    }
  }

  mutating func appendInitializer(from initializer: InitializerDeclSyntax) throws {
    guard let declaration = try PreviewableDoubleMemberBuilder.initializerDeclaration(
      from: initializer,
      access: access,
      isolated: isolated,
      sendable: sendable,
      index: index
    ) else { return }
    result.declarations.append(declaration)
  }

  mutating func append(
    stubs: [String],
    declaration: String,
    isStatic: Bool
  ) {
    if isStatic {
      result.staticStubs += stubs
    } else {
      result.stubs += stubs
    }
    result.declarations.append(declaration)
  }
}
