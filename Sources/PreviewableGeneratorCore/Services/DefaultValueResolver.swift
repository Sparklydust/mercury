//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Resolves default expressions from type syntax and the module's annotated construction recipes.
///
/// Unsupported construction raises `GenerationError`. Fake value allocations and throwing effects update
/// resolver state; callers reset the throwing flag before resolving each independent field.
struct DefaultValueResolver {

  /// The module declarations available for default construction.
  let index: ModuleIndex
  /// The policy selecting neutral double defaults or populated fake defaults.
  let context: DefaultContext

  /// Generic parameter names of the enclosing declaration, which can never be defaulted.
  var genericParameters: Set<String> = []
  /// The property or method name included in resolution failures.
  var fieldName = "default"
  /// Whether resolution encountered an eager throwing factory since the caller last reset the flag.
  var usedThrowingDefault = false

  /// The distinct values already emitted.
  var values = FakeDefaultValues()

  /// Returns whether the supplied type carries no value.
  static func isVoid(_ type: TypeSyntax) -> Bool {
    ["Void", "Swift.Void", "()"].contains(type.trimmedDescription)
  }

  /// Returns a compilable default expression for the supplied type.
  /// - Parameter type: The qualified type whose default expression is required.
  /// - Throws: `GenerationError` when no correct default can be synthesised.
  mutating func defaultValue(for type: TypeSyntax) throws -> String {
    let writtenType = type.trimmedDescription
    let type = try resolvedType(type)
    if let attributed = type.as(AttributedTypeSyntax.self) {
      return try defaultValue(for: attributed.baseType)
    }
    if type.is(OptionalTypeSyntax.self) || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
      return ".none"
    }
    if let function = type.as(FunctionTypeSyntax.self) {
      return try closureLiteral(for: function)
    }
    if type.is(ArrayTypeSyntax.self) { return "[]" }
    if type.is(DictionaryTypeSyntax.self) { return "[:]" }
    if let tuple = type.as(TupleTypeSyntax.self) {
      return try tupleLiteral(for: tuple)
    }
    if let existential = type.as(SomeOrAnyTypeSyntax.self) {
      return try defaultValue(for: existential.constraint)
    }
    if let member = type.as(MemberTypeSyntax.self) {
      return try nominalDefault(
        named: member.trimmedDescription,
        simpleName: member.name.text,
        genericArguments: arguments(of: member.genericArgumentClause)
      )
    }
    if let identifier = type.as(IdentifierTypeSyntax.self) {
      return try nominalDefault(
        named: identifier.name.text,
        simpleName: identifier.name.text,
        genericArguments: arguments(of: identifier.genericArgumentClause)
      )
    }
    throw GenerationError.message(
      "cannot synthesise a default for '\(writtenType)' — no automatic default is available"
    )
  }

  /// Expands local aliases without changing the declared factory or requirement signature.
  /// - Parameter type: A type already qualified in its declaration scope.
  /// - Throws: `GenerationError` for cyclic aliases.
  func resolvedType(_ type: TypeSyntax) throws -> TypeSyntax {
    try DoubleTypeCanonicalizer(
      index: index, scope: [],
      substitutions: Dictionary(uniqueKeysWithValues: genericParameters.map { ($0, $0) })
    ).resolved(type)
  }
}

private extension DefaultValueResolver {

  /// Extracts type arguments, returning an empty list when no generic clause is present.
  /// - Parameter clause: The written generic argument clause.
  func arguments(of clause: GenericArgumentClauseSyntax?) -> [TypeSyntax] {
    clause?.arguments.compactMap { TypeSyntax($0.argument) } ?? []
  }

  /// Renders a closure whose result is generated when the closure is called.
  /// - Parameter function: The closure signature to default.
  /// - Throws: `GenerationError` for unavailable results or throwing construction in a nonthrowing closure.
  mutating func closureLiteral(for function: FunctionTypeSyntax) throws -> String {
    let count = function.parameters.count
    let placeholders = Array(repeating: "_", count: count).joined(separator: ", ")
    let returnType = function.returnClause.type
    guard !Self.isVoid(returnType) else {
      return count == 0 ? "{ }" : "{ \(placeholders) in }"
    }
    let previous = usedThrowingDefault
    usedThrowingDefault = false
    let value = try defaultValue(for: returnType)
    let throwsOnCall = usedThrowingDefault
    usedThrowingDefault = previous
    if throwsOnCall && function.effectSpecifiers?.throwsClause == nil {
      throw GenerationError.message("'\(fieldName)' requires a throwing closure to construct its return value")
    }
    return count == 0 ? "{ \(value) }" : "{ \(placeholders) in \(value) }"
  }

  /// Renders tuple element defaults while preserving labels and propagating eager throwing effects.
  /// - Parameter tuple: The tuple or parenthesized type to default.
  /// - Throws: `GenerationError` when an element has no supported default.
  mutating func tupleLiteral(for tuple: TupleTypeSyntax) throws -> String {
    guard !tuple.elements.isEmpty else { return "()" }
    // A single unlabelled element is a parenthesised type, not a one-element tuple.
    if tuple.elements.count == 1, let only = tuple.elements.first, only.firstName == nil {
      return try defaultValue(for: only.type)
    }
    var elements: [String] = []
    for element in tuple.elements {
      let value = try defaultValue(for: element.type)
      if let label = element.firstName?.text, label != "_" {
        elements.append("\(label): \(value)")
      } else {
        elements.append(value)
      }
    }
    return "(\(elements.joined(separator: ", ")))"
  }

  /// Resolves an enumeration, annotated declaration, or supported external type to a default expression.
  /// - Parameters:
  ///   - name: The qualified or written nominal type name.
  ///   - simpleName: The final component used for known types and generated double names.
  ///   - genericArguments: The written type arguments.
  /// - Throws: `GenerationError` when the nominal type cannot be constructed automatically.
  mutating func nominalDefault(
    named name: String,
    simpleName: String,
    genericArguments: [TypeSyntax]
  ) throws -> String {
    if genericParameters.contains(name) {
      throw GenerationError.message(
        "cannot synthesise a default for generic parameter '\(name)' — no automatic default is available"
      )
    }
    if let enumDefault = index.enumDefaults[name] {
      return enumDefault
    }
    if index.protocols[name] != nil {
      return try protocolDefault(named: name, simpleName: simpleName)
    }
    if index.declaresType(name) || index.fakeAnnotatedTypes.contains(name) {
      return try ownedTypeDefault(named: name, simpleName: simpleName)
    }
    let standardName = name.hasPrefix("Swift.") || name.hasPrefix("Foundation.") ? simpleName : name
    if let known = try knownDefault(named: standardName, genericArguments: genericArguments) { return known }
    guard genericArguments.isEmpty else {
      throw GenerationError.message(
        "cannot synthesise a default for generic type '\(name)' — no automatic default is available"
      )
    }
    throw GenerationError.message(
      "cannot synthesise a default for '\(fieldName)' of type '\(name)' — declare an explicit @PreviewableFake construction"
    )
  }

  /// Returns an expression for a supported built-in type, or `nil` when the name is unrecognized.
  /// - Parameters:
  ///   - name: The normalized type name used for built-in lookup.
  ///   - genericArguments: Type arguments used to construct a `Result` success value.
  /// - Throws: `GenerationError` when a nested success value has no supported default.
  mutating func knownDefault(
    named name: String,
    genericArguments: [TypeSyntax]
  ) throws -> String? {
    switch name {
    case "Bool": return "false"
    case "String", "Substring":
      return context == .fake ? values.string() : ".init()"
    case "Void": return "()"
    case "Optional": return ".none"
    case "Array", "Set", "ContiguousArray": return "[]"
    case "Dictionary": return "[:]"
    case "Date":
      return context == .fake ? values.date() : ".now"
    case "UUID":
      return context == .fake ? values.uuid() : "UUID()"
    case "URL":
      return context == .fake ? values.url() : "URL(string: \"https://example.com\")!"
    case "Image": return "Image(systemName: \"photo\")"
    case "Data": return "Data()"
    case "Character": return "\"a\""
    case "Result":
      guard let success = genericArguments.first else { return nil }
      return ".success(\(try defaultValue(for: success)))"
    default:
      guard Self.numericTypes.contains(name) else { return nil }
      return context == .fake ? values.number(for: name) : ".zero"
    }
  }

  /// Returns a fresh double construction expression for an annotated protocol.
  /// - Parameters:
  ///   - name: The protocol name used to locate its annotation.
  ///   - simpleName: The unqualified name used to derive the double name.
  /// - Throws: `GenerationError` when the protocol lacks a double annotation.
  func protocolDefault(named name: String, simpleName: String) throws -> String {
    guard index.annotatedProtocols[name] != nil else {
      throw GenerationError.message(
        "'\(name)' must be annotated with @PreviewableDouble to be used as a requirement type"
      )
    }
    return "\(PreviewableDoubleNaming.doubleName(for: simpleName))()"
  }

  /// Returns a fake factory call and records any eager throwing effect.
  /// - Parameters:
  ///   - name: The type name used for annotation lookup and the factory call.
  ///   - simpleName: The unqualified type name; reserved by this resolver interface.
  /// - Throws: `GenerationError` for generic types, missing annotations, or throwing defaults in doubles.
  mutating func ownedTypeDefault(named name: String, simpleName: String) throws -> String {
    if index.genericTypes.contains(name) {
      throw GenerationError.message(
        "cannot synthesise a default for generic type '\(name)' — no automatic default is available"
      )
    }
    guard index.fakeAnnotatedTypes.contains(name)
    else {
      throw GenerationError.message(
        "'\(name)' must be annotated with @PreviewableFake to be used as a requirement type"
      )
    }
    if index.throwingFakes.contains(name) {
      guard context == .fake else {
        throw GenerationError.message("'\(fieldName)' needs throwing factory '\(name).fake()' in a nonthrowing double")
      }
      usedThrowingDefault = true
      return "try \(name).fake()"
    }
    return "\(name).fake()"
  }

  /// Type names supported by numeric default generation.
  static let numericTypes: Set<String> = [
    "Double", "Float", "Float16", "Float32", "Float64", "Float80",
    "Int", "Int8", "Int16", "Int32", "Int64",
    "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
    "CGFloat", "TimeInterval", "Decimal",
  ]

}
