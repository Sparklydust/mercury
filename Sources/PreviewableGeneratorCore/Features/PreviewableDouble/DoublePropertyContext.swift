//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

/// Renders a property response and witness using the declaration's isolation contract.
struct DoublePropertyContext {

  let declaration: VariableDeclSyntax
  let access: String
  let isolated: Bool
  let sendable: Bool
  let isolation: String

  private var nonisolated: Bool { declaration.modifiers.contains { $0.name.text == "nonisolated" } }
  private var modifier: String {
    (nonisolated ? "nonisolated " : "") + (declaration.modifiers.isStatic ? "static " : "")
  }
  private var memberIsolated: Bool { !nonisolated && (isolated || !isolation.isEmpty) }
  private var attributes: String {
    declaration.attributes.isEmpty ? "" : declaration.attributes.trimmedDescription + "\n"
  }

  /// Renders response storage and a property witness, retaining async getter effects.
  /// - Parameters:
  ///   - binding: The named, explicitly typed property requirement.
  ///   - seen: Names already emitted in this instance or static dispatch scope.
  ///   - resolver: The resolver whose state allocates property defaults.
  /// - Returns: The generated property, or `nil` if its name was already emitted.
  /// - Throws: `GenerationError` for unsupported declarations, types, or defaults.
  func property(
    from binding: PatternBindingSyntax,
    seen: inout Set<String>,
    resolver: inout DefaultValueResolver
  ) throws -> GeneratedProperty? {
    let components = try validatedComponents(of: binding)

    guard seen.insert(components.name).inserted else { return nil }
    try validateType(components.type, name: components.name)
    resolver.fieldName = components.name

    if let getter = components.accessors.asyncGetter {
      return try DoubleAsyncPropertyBuilder.generate(
        context: self,
        getter: getter,
        name: components.name,
        type: components.type,
        signature: signature(name: components.name, type: components.type),
        resolver: &resolver
      )
    }
    let value = try DoubleResponseDefaultResolver.resolve(for: components.type, resolver: &resolver)
    let stub = DoubleStorageBuilder.property(
      name: components.name + "Stub",
      type: components.type.trimmedDescription,
      value: value,
      access: access,
      isolated: !sendable || memberIsolated,
      documentation: "The configured property value; assignments update this stub.",
      isolation: isolation,
      nonisolated: nonisolated
    )

    return GeneratedProperty(
      stub: stub,
      requirement: witness(name: components.name, type: components.type, settable: components.accessors.isSettable)
    )
  }

  private func validatedComponents(
    of binding: PatternBindingSyntax
  ) throws -> (name: String, type: TypeSyntax, accessors: AccessorBlockSyntax) {
    guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
          let type = binding.typeAnnotation?.type,
          let accessors = binding.accessorBlock
   else { throw GenerationError.message("@PreviewableDouble requires named, explicitly typed protocol properties") }

    return (identifier.identifier.text, type, accessors)
  }

  private func validateType(
    _ type: TypeSyntax,
    name: String
  ) throws {
    guard !type.usesSelfType else {
      throw GenerationError.message("@PreviewableDouble does not support 'Self' in requirement '\(name)'")
    }
  }

  private func witness(
    name: String,
    type: TypeSyntax,
    settable: Bool
  ) -> String {
    let signature = signature(name: name, type: type)

    guard settable else { return "\(signature) { \(name)Stub }" }
    return """
      \(signature) {
        get { \(name)Stub }
        set { \(name)Stub = newValue }
      }
      """
  }

  private func signature(name: String, type: TypeSyntax) -> String {
    "\(attributes)\(access)\(modifier)var \(name): \(type.trimmedDescription)"
  }
}
