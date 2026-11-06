//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import SwiftParser
import SwiftSyntax

/// Describes one requirement using a canonical identity separate from its original Swift declaration.
struct DoubleRequirement {

  var declaration: MemberBlockItemSyntax
  let function: FunctionDeclSyntax?
  let subscriptDeclaration: SubscriptDeclSyntax?
  let name: String
  let isStatic: Bool
  let identity: String
  let shape: String
  let isolation: String
  let friendlyParameters: String
  let friendlyResult: String
  var stubName: String
  var recordingKey: String?

  /// Collects requirements, deduplicates inherited equivalents, and allocates deterministic stub names.
  /// - Parameters:
  ///   - members: Requirements after associated-type substitution.
  ///   - index: Local types and aliases used to establish canonical identities.
  ///   - scope: The annotated protocol's enclosing scope.
  ///   - defaultIsolation: The protocol's declared or inherited global actor.
  /// - Throws: For alias cycles, incompatible inherited properties, or incompatible isolation.
  static func collect(
    _ members: [MemberBlockItemSyntax],
    index: ModuleIndex,
    scope: [String],
    defaultIsolation: String
  ) throws -> [Self] {
    var requirements = try uniqueRequirements(
      in: flattened(members),
      index: index,
      scope: scope,
      defaultIsolation: defaultIsolation
    )
    allocateStubNames(in: &requirements)
    return requirements
  }

  private static func flattened(_ members: [MemberBlockItemSyntax]) -> [MemberBlockItemSyntax] {
    members.flatMap { member -> [MemberBlockItemSyntax] in
      if let variable = member.decl.as(VariableDeclSyntax.self), variable.bindings.count > 1 {
        return variable.bindings.map { binding in
          var single = variable
          single.bindings = PatternBindingListSyntax([binding.with(\.trailingComma, nil)])
          var item = member
          item.decl = DeclSyntax(single)
          return item
        }
      }

      return [member]
    }
  }

  /// Deduplicates inherited identities, retaining writable witnesses and rejecting incompatible declarations.
  private static func uniqueRequirements(
    in flattened: [MemberBlockItemSyntax],
    index: ModuleIndex,
    scope: [String],
    defaultIsolation: String
  ) throws -> [Self] {
    var requirements: [Self] = []
    var positions: [String: Int] = [:]
    var properties: [String: String] = [:]
    var isolations: [String: String] = [:]

    for member in flattened {
      let requirement = try Self(member, index: index, scope: scope, defaultIsolation: defaultIsolation)

      if let previous = isolations[requirement.shape], previous != requirement.isolation {
        throw GenerationError.message("@PreviewableDouble requirement '\(requirement.name)' has incompatible isolation")
      }
      isolations[requirement.shape] = requirement.isolation
      if requirement.declaration.decl.is(VariableDeclSyntax.self) {
        let key = "\(requirement.isStatic):\(requirement.name)"

        if let previous = properties[key], previous != requirement.identity {
          throw GenerationError.message(
            "@PreviewableDouble property '\(requirement.name)' has incompatible requirements"
          )
        }
        properties[key] = requirement.identity
      }
      if let position = positions[requirement.identity] {
        // A writable property or subscript also witnesses an inherited read-only declaration.
        requirements[position] = DoublePropertyRequirementMerger.merge(requirements[position], requirement)
        continue
      }
      positions[requirement.identity] = requirements.count
      requirements.append(requirement)
    }

    return requirements
  }

  private static func allocateStubNames(in requirements: inout [Self]) {
    let groups = Dictionary(grouping: requirements.indices.filter { requirements[$0].function != nil }) {
      "\(requirements[$0].isStatic):\(requirements[$0].name)"
    }
    for group in groups.values where group.count > 1 {
      for offset in group {
        requirements[offset].stubName = requirements[offset].name + requirements[offset].friendlyParameters
        requirements[offset].recordingKey = requirements[offset].identity
      }
      let names = Dictionary(grouping: group) { requirements[$0].stubName }

      for collisions in names.values where collisions.count > 1 {
        for offset in collisions {
          requirements[offset].stubName += "Returning" + requirements[offset].friendlyResult
        }
      }
      let results = Dictionary(grouping: group) { requirements[$0].stubName }

      for collisions in results.values where collisions.count > 1 {
        for offset in collisions {
          requirements[offset].stubName += signatureSuffix(requirements[offset].identity)
        }
      }
    }
    // A readable overload name can also match another method or a property in the same dispatch scope.
    let allocated = Dictionary(grouping: requirements.indices) {
      "\(requirements[$0].isStatic):\(requirements[$0].stubName)"
    }
    for collisions in allocated.values where collisions.count > 1 {
      for offset in collisions where requirements[offset].function != nil {
        requirements[offset].stubName += signatureSuffix(requirements[offset].identity)
        requirements[offset].recordingKey = requirements[offset].identity
      }
    }
  }

  /// Disambiguates otherwise identical display names without depending on declaration order.
  private static func signatureSuffix(_ identity: String) -> String {
    let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    return "Signature" + digest.prefix(12)
  }

  /// Indicates whether this property-like requirement must witness a setter.
  var isSettable: Bool {

    if let subscriptDeclaration {
      return subscriptDeclaration.accessorBlock?.isSettable ?? false
    }

    return declaration.decl.as(VariableDeclSyntax.self)?.bindings.first?.accessorBlock?.isSettable ?? false
  }

  /// Creates the canonical identity and display components of a single requirement.
  private init(
    _ member: MemberBlockItemSyntax,
    index: ModuleIndex,
    scope: [String],
    defaultIsolation: String
  ) throws {
    let syntax = DoubleRequirementSyntax(member)
    declaration = member
    subscriptDeclaration = syntax.subscriptDeclaration
    function = syntax.function
    isStatic = syntax.modifiers.isStatic
    name = syntax.name
    stubName = name
    isolation = Self.effectiveIsolation(syntax, index: index, scope: scope, defaultIsolation: defaultIsolation)
    let components = try Self.identityComponents(syntax, index: index, scope: scope)
    shape = components.shape
    friendlyParameters = components.parameters
    friendlyResult = components.result
    identity = shape + (isolation.isEmpty ? "" : " " + isolation.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private static func effectiveIsolation(
    _ syntax: DoubleRequirementSyntax,
    index: ModuleIndex,
    scope: [String],
    defaultIsolation: String
  ) -> String {
    let actor = DoubleStorageBuilder.isolationAttributes(in: syntax.attributes, index: index, scope: scope)
    let effectiveActor = actor.isEmpty ? defaultIsolation : actor

    return syntax.modifiers.contains { $0.name.text == "nonisolated" }
    ? "nonisolated"
    : effectiveActor.replacingOccurrences(of: "@Swift.MainActor", with: "@MainActor")
      .replacingOccurrences(of: "@_Concurrency.MainActor", with: "@MainActor")
  }

  private static func identityComponents(
    _ syntax: DoubleRequirementSyntax,
    index: ModuleIndex,
    scope: [String]
  ) throws -> (shape: String, parameters: String, result: String) {
    let canonicalizer = DoubleTypeCanonicalizer(index: index, scope: scope)
    let dispatch = syntax.modifiers.isStatic ? "static " : ""

    if let function = syntax.function {
      let components = try Self.functionIdentity(
        function,
        name: syntax.name,
        dispatch: dispatch,
        index: index,
        scope: scope
      )
      return components
    } else if let variable = syntax.variable, let type = variable.bindings.first?.typeAnnotation?.type {
      return (dispatch + "var " + syntax.name + ":" + (try canonicalizer.canonical(type)), "", "")
    } else {
      return (syntax.member.trimmedDescription, "", "")
    }
  }

  /// Canonicalizes generic names by position so equivalent inherited signatures share an identity.
  private static func functionIdentity(
    _ function: FunctionDeclSyntax,
    name: String,
    dispatch: String,
    index: ModuleIndex,
    scope: [String]
  ) throws -> (shape: String, parameters: String, result: String) {
    let generics = function.genericParameterClause?.parameters.map(\.name.text) ?? []
    let substitutions = Dictionary(uniqueKeysWithValues: generics.enumerated().map { ($0.element, "_G\($0.offset)") })
    let canonicalizer = DoubleTypeCanonicalizer(index: index, scope: scope, substitutions: substitutions)
    let parameters = try function.signature.parameterClause.parameters.map {
      ($0.firstName.text, try canonicalizer.canonical($0.type))
    }
    let result = try function.signature.returnClause.map { try canonicalizer.canonical($0.type) } ?? "Swift.Void"
    let constraints = try Self.constraints(of: function, canonicalizer: canonicalizer, substitutions: substitutions)
    let effects = function.signature.effectSpecifiers
    var suffix = effects?.asyncSpecifier == nil ? "" : " async"

    if let clause = effects?.throwsClause {
      suffix += " " + clause.throwsSpecifier.text
      if let type = clause.type {
        suffix += "(" + (try canonicalizer.canonical(type)) + ")"
      }
    }
    let genericIdentity =
    generics.isEmpty ? "" : "<" + generics.indices.map { "_G\($0)" }.joined(separator: ",") + ">"
    let shape =
    dispatch + name + genericIdentity + "("
    + parameters.map { "\($0.0):\($0.1)" }.joined(separator: ",") + ") -> " + result
    + suffix + (constraints.isEmpty ? "" : " where " + constraints.joined(separator: ","))
    let friendlyParameters = parameters.map { ($0.0 == "_" ? "" : Self.friendly($0.0)) + Self.friendly($0.1) }.joined()
    let friendlyResult = Self.friendly(result)

    return (shape, friendlyParameters, friendlyResult)
  }

  /// Flattens inline and where-clause constraints into a sorted, duplicate-free identity.
  private static func constraints(
    of function: FunctionDeclSyntax,
    canonicalizer: DoubleTypeCanonicalizer,
    substitutions: [String: String]
  ) throws -> [String] {
    var result: Set<String> = []

    for parameter in function.genericParameterClause?.parameters ?? [] {
      if let type = parameter.inheritedType {
        try insertConstraint(substitutions[parameter.name.text]!, type, canonicalizer: canonicalizer, into: &result)
      }
    }

    for item in function.genericWhereClause?.requirements ?? [] {
      switch item.requirement {
      case .conformanceRequirement(let requirement):
        try insertConstraint(
          canonicalizer.canonical(requirement.leftType),
          requirement.rightType,
          canonicalizer: canonicalizer,
          into: &result
        )
      case .sameTypeRequirement(let requirement):
        guard let left = requirement.leftType.as(TypeSyntax.self),
              let right = requirement.rightType.as(TypeSyntax.self)
        else { throw GenerationError.message("@PreviewableDouble does not support value-dependent generic constraints") }

        result.insert(
          try [canonicalizer.canonical(left), canonicalizer.canonical(right)]
            .sorted().joined(separator: "==")
        )
      default: result.insert(item.tokens(viewMode: .sourceAccurate).map(\.text).joined())
      }
    }

    return result.sorted()
  }

  private static func insertConstraint(
    _ left: String,
    _ type: TypeSyntax,
    canonicalizer: DoubleTypeCanonicalizer,
    into result: inout Set<String>
  ) throws {
    if let composition = type.as(CompositionTypeSyntax.self) {
      for element in composition.elements {
        try insertConstraint(left, element.type, canonicalizer: canonicalizer, into: &result)
      }
    } else {
      result.insert(left + ":" + (try canonicalizer.canonical(type)))
    }
  }

  /// Converts canonical type tokens to a readable identifier component.
  private static func friendly(_ text: String) -> String {
    text.replacingOccurrences(of: "Swift.", with: "")
      .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
      .map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
  }

  /// Models a subscript getter as a callable while retaining all index argument types.
  static func getterFunction(_ declaration: SubscriptDeclSyntax) -> FunctionDeclSyntax {
    var parameters = declaration.parameterClause
    parameters.parameters = FunctionParameterListSyntax(
      declaration.parameterClause.parameters.map { parameter in
        if let second = parameter.secondName {
          guard second.text == parameter.firstName.text else { return parameter }
          return parameter.with(\.secondName, nil)
        }
        var copy = parameter
        copy.firstName = .wildcardToken(trailingTrivia: .space)
        copy.secondName = parameter.firstName.with(\.leadingTrivia, [])
        return copy
      }
    )
    let effects = if case .accessors(let accessors)? = declaration.accessorBlock?.accessors {
      accessors
        .first { $0.accessorSpecifier.text == "get" }?
        .effectSpecifiers?
        .trimmedDescription ?? ""
    } else {
      ""
    }

    let source = "\(declaration.attributes) \(declaration.modifiers)func _previewableSubscript"
    + "\(declaration.genericParameterClause?.trimmedDescription ?? "")\(parameters) \(effects) "
    + "\(declaration.returnClause) \(declaration.genericWhereClause?.trimmedDescription ?? "") {}"

    return Parser.parse(source: source).statements.first!.item.as(FunctionDeclSyntax.self)!
  }
}
