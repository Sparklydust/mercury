//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Resolves protocol associated types into explicit generic parameters and concrete aliases.
struct DoubleAssociatedTypes {

  let parameters: [String]
  let bindings: [String: String]
  let constraints: [String]

  /// The generated double's generic parameter clause.
  var genericClause: String { parameters.isEmpty ? "" : "<" + parameters.joined(separator: ", ") + ">" }
  /// The constraints involving the generated generic parameters.
  var whereClause: String { constraints.isEmpty ? "" : " where " + constraints.joined(separator: ", ") }

  /// Resolves primary, inherited, and same-type-constrained associated types.
  /// - Parameters:
  ///   - declaration: The annotated protocol.
  ///   - members: Flattened local requirements, including associated types.
  ///   - index: Locally available declarations.
  ///   - isolated: Whether the protocol has global-actor isolation.
  ///   - sendable: Whether instances must support transfer between isolation domains.
  /// - Throws: For missing associated declarations, incompatible concrete bindings, or recursive bindings.
  init(
    declaration: ProtocolDeclSyntax,
    members: [MemberBlockItemSyntax],
    index: ModuleIndex,
    isolated: Bool,
    sendable: Bool
  ) throws {
    let associated = members.compactMap { $0.decl.as(AssociatedTypeDeclSyntax.self) }
    let names = Set(associated.map(\.name.text))
    let ordered = try Self.orderedNames(in: declaration, names: names)
    let conditions = Self.collectedConditions(
      associated: associated,
      declaration: declaration,
      names: names,
      index: index
    )
    let aliases = try Self.resolvedAliases(
      ordered: ordered,
      names: names,
      conditions: conditions,
      declaration: declaration,
      index: index
    )
    let generated = try Self.resolvedBindings(ordered: ordered, names: names, aliases: aliases)

    bindings = generated
    parameters = ordered.filter { aliases[$0] == nil }.compactMap { generated[$0] }
    constraints = Self.resolvedConstraints(
      conditions: conditions,
      generated: generated,
      parameters: Set(parameters),
      members: members,
      index: index,
      isolated: isolated,
      sendable: sendable
    )
  }

  /// Renders explicit aliases without relying on associated-type inference.
  /// - Parameter access: The declaration's effective access prefix.
  func aliases(access: String) -> String {
    bindings.sorted { $0.key < $1.key }
      .map { "\(access)typealias \($0.key) = \($0.value)" }
      .joined(separator: "\n")
  }
}

extension DoubleAssociatedTypes {

  private static func orderedNames(
    in declaration: ProtocolDeclSyntax,
    names: Set<String>
  ) throws -> [String] {
    let primary = declaration.primaryAssociatedTypeClause?.primaryAssociatedTypes.map(\.name.text) ?? []

    guard Set(primary).isSubset(of: names) else {
      throw GenerationError.message("@PreviewableDouble primary associated types must have associatedtype declarations")
    }

    return primary + names.subtracting(primary).sorted()
  }

  private static func collectedConditions(
    associated: [AssociatedTypeDeclSyntax],
    declaration: ProtocolDeclSyntax,
    names: Set<String>,
    index: ModuleIndex
  ) -> [(String, String, String)] {
    var conditions: [(String, String, String)] = []

    for item in associated {
      for inherited in item.inheritanceClause?.inheritedTypes ?? [] {
        conditions.append((item.name.text, ":", inherited.type.trimmedDescription))
      }
      conditions += Self.conditions(item.genericWhereClause)
    }
    var visited: Set<String> = []
    collectConstraints(from: declaration, names: names, index: index, visited: &visited, result: &conditions)
    return conditions
  }

  /// Collects inherited constraints in their original declaration scope, visiting each protocol once.
  private static func collectConstraints(
    from protocolDeclaration: ProtocolDeclSyntax,
    names: Set<String>,
    index: ModuleIndex,
    visited: inout Set<String>,
    result: inout [(String, String, String)]
  ) {
    let name = index.protocols.first { $0.value.id == protocolDeclaration.id }?.key ?? protocolDeclaration.name.text

    guard visited.insert(name).inserted else { return }

    if let clause = protocolDeclaration.genericWhereClause {
      let qualifier = TypeNameResolver(
        index: index,
        scope: name.split(separator: ".").map(String.init),
        genericParameters: names
      )
      result += Self.conditions(qualifier.rewrite(clause).cast(GenericWhereClauseSyntax.self))
    }

    for inherited in protocolDeclaration.inheritanceClause?.inheritedTypes ?? [] {
      guard let key = index.resolve(
        inherited.type.trimmedDescription,
        scope: name.split(separator: ".").map(String.init)
      ), let base = index.protocols[key]
      else { continue }

      collectConstraints(
        from: base,
        names: names,
        index: index,
        visited: &visited,
        result: &result
      )
    }
  }

  private static func representative(
    _ name: String,
    in representatives: [String: String]
  ) -> String {
    var current = name

    while let next = representatives[current], next != current {
      current = next
    }
    return current
  }

  /// Unites equivalent associated names before checking their concrete bindings for compatibility.
  /// - Throws: When an associated identity has incompatible concrete bindings.
  private static func resolvedAliases(
    ordered: [String],
    names: Set<String>,
    conditions: [(String, String, String)],
    declaration: ProtocolDeclSyntax,
    index: ModuleIndex
  ) throws -> [String: String] {

    let representatives = mergedRepresentatives(ordered: ordered, names: names, conditions: conditions)
    var aliases = equivalentAliases(ordered: ordered, representatives: representatives)
    let canonicalizer = bindingCanonicalizer(for: declaration, index: index)

    try applyConcreteBindings(
      conditions: conditions,
      names: names,
      representatives: representatives,
      canonicalizer: canonicalizer,
      aliases: &aliases
    )
    return aliases
  }

  /// Merges associated identities in primary-parameter order before any concrete binding is applied.
  private static func mergedRepresentatives(
    ordered: [String],
    names: Set<String>,
    conditions: [(String, String, String)]
  ) -> [String: String] {

    var representatives = Dictionary(uniqueKeysWithValues: ordered.map { ($0, $0) })

    for (rawLeft, relation, rawRight) in conditions where relation == "==" {
      let left = rawLeft.replacingOccurrences(of: "Self.", with: "")
      let right = rawRight.replacingOccurrences(of: "Self.", with: "")

      if names.contains(left), names.contains(right) {
        let lhs = representative(left, in: representatives)
        let rhs = representative(right, in: representatives)
        let first = ordered.firstIndex(of: lhs)!
        let second = ordered.firstIndex(of: rhs)!
        representatives[first < second ? rhs : lhs] = first < second ? lhs : rhs
      }
    }
    return representatives
  }

  private static func equivalentAliases(
    ordered: [String],
    representatives: [String: String]
  ) -> [String: String] {
    var aliases: [String: String] = [:]

    for name in ordered {
      let root = representative(name, in: representatives)
      if root != name {
        aliases[name] = root
      }
    }
    return aliases
  }

  private static func bindingCanonicalizer(
    for declaration: ProtocolDeclSyntax,
    index: ModuleIndex
  ) -> DoubleTypeCanonicalizer {

    let name = index.protocols
      .first { $0.value.id == declaration.id }?
      .key ?? declaration.name.text

    return DoubleTypeCanonicalizer(
      index: index,
      scope: name.split(separator: ".").map(String.init)
    )
  }

  private static func applyConcreteBindings(
    conditions: [(String, String, String)],
    names: Set<String>,
    representatives: [String: String],
    canonicalizer: DoubleTypeCanonicalizer,
    aliases: inout [String: String]
  ) throws {

    for (rawLeft, relation, rawRight) in conditions where relation == "==" {
      let left = rawLeft.replacingOccurrences(of: "Self.", with: "")
      let right = rawRight.replacingOccurrences(of: "Self.", with: "")

      if names.contains(left), let type = TypeSyntax.parsed(from: right),
         names.isDisjoint(with: type.writtenTypeNames) {
        try bind(left, to: right, representatives: representatives, canonicalizer: canonicalizer, aliases: &aliases)
      } else if names.contains(right), let type = TypeSyntax.parsed(from: left),
                names.isDisjoint(with: type.writtenTypeNames) {
        try bind(right, to: left, representatives: representatives, canonicalizer: canonicalizer, aliases: &aliases)
      }
    }
  }

  private static func bind(
    _ name: String,
    to expression: String,
    representatives: [String: String],
    canonicalizer: DoubleTypeCanonicalizer,
    aliases: inout [String: String]
  ) throws {
    let root = representative(name, in: representatives)

    if let existing = aliases[root], let previous = TypeSyntax.parsed(from: existing),
       let next = TypeSyntax.parsed(from: expression),
       try canonicalizer.canonical(previous) != canonicalizer.canonical(next) {
      throw GenerationError.message("@PreviewableDouble associated type '\(name)' has incompatible same-type bindings")
    }

    aliases[root] = expression
  }

  /// Allocates collision-free generic names and resolves aliases against those names.
  /// - Throws: When resolving an alias revisits a type already being resolved.
  private static func resolvedBindings(
    ordered: [String],
    names: Set<String>,
    aliases: [String: String]
  ) throws -> [String: String] {

    var generated: [String: String] = [:]
    var occupied = names

    for name in ordered where aliases[name] == nil {
      var parameter = "_Previewable" + name

      while occupied.contains(parameter) {
        parameter += "_"
      }
      occupied.insert(parameter)
      generated[name] = parameter
    }
    var resolving: Set<String> = []

    for name in ordered {
      _ = try resolve(name, names: names, aliases: aliases, generated: &generated, resolving: &resolving)
    }

    return generated
  }

  private static func resolve(
    _ name: String,
    names: Set<String>,
    aliases: [String: String],
    generated: inout [String: String],
    resolving: inout Set<String>
  ) throws -> String {
    if let value = generated[name] {
      return value
    }

    guard resolving.insert(name).inserted else {
      throw GenerationError.message("@PreviewableDouble associated type '\(name)' has a recursive same-type binding")
    }
    defer { resolving.remove(name) }
    guard let expression = aliases[name], let type = TypeSyntax.parsed(from: expression) else { return name }

    var replacements: [String: String] = [:]

    for dependency in Set(type.writtenTypeNames).intersection(names) {
      replacements[dependency] = try resolve(
        dependency,
        names: names,
        aliases: aliases,
        generated: &generated,
        resolving: &resolving
      )
    }

    let value = DoubleTypeSubstitution(replacements).rewrite(type).trimmedDescription
    generated[name] = value
    return value
  }

  private static func resolvedConstraints(
    conditions: [(String, String, String)],
    generated: [String: String],
    parameters generics: Set<String>,
    members: [MemberBlockItemSyntax],
    index: ModuleIndex,
    isolated: Bool,
    sendable: Bool
  ) -> [String] {

    let rewriter = DoubleTypeSubstitution(generated)
    var resolved: Set<String> = []

    for (left, relation, right) in conditions {
      guard let leftType = TypeSyntax.parsed(from: left), let rightType = TypeSyntax.parsed(from: right)
      else { continue }

      let lhs = rewriter.rewrite(leftType).cast(TypeSyntax.self)
      let rhs = rewriter.rewrite(rightType).cast(TypeSyntax.self)

      guard relation != "==" || lhs.trimmedDescription != rhs.trimmedDescription,
            !generics.isDisjoint(with: lhs.writtenTypeNames + rhs.writtenTypeNames)
      else { continue }

      resolved.insert(lhs.trimmedDescription + " " + relation + " " + rhs.trimmedDescription)
    }

    resolved.formUnion(
      sendableConstraints(
        members: members,
        rewriter: rewriter,
        generics: generics,
        index: index,
        isolated: isolated,
        sendable: sendable
      )
    )

    return resolved.sorted()
  }

  /// Requires Sendable components only for requirements whose storage crosses an isolation boundary.
  private static func sendableConstraints(
    members: [MemberBlockItemSyntax],
    rewriter: DoubleTypeSubstitution,
    generics: Set<String>,
    index: ModuleIndex,
    isolated: Bool,
    sendable: Bool
  ) -> Set<String> {
    var resolved: Set<String> = []

    for member in members {
      let syntax = rewriter.rewrite(member)
      let function = syntax.as(MemberBlockItemSyntax.self)?.decl.as(FunctionDeclSyntax.self)
      let variable = syntax.as(MemberBlockItemSyntax.self)?.decl.as(VariableDeclSyntax.self)
      let subscriptDeclaration = syntax.as(MemberBlockItemSyntax.self)?.decl.as(SubscriptDeclSyntax.self)
      let attributes = function?.attributes ?? variable?.attributes ?? subscriptDeclaration?.attributes ?? []
      let modifiers = function?.modifiers ?? variable?.modifiers ?? subscriptDeclaration?.modifiers ?? []

      guard sendable || modifiers.isStatic else { continue }
      let nonisolated = modifiers.contains { $0.name.text == "nonisolated" }

      guard nonisolated || (!isolated && DoubleStorageBuilder.isolationAttributes(in: attributes, index: index).isEmpty),
            function != nil || variable != nil || subscriptDeclaration != nil
      else { continue }

      let collector = AssociatedSendableCollector(parameters: generics)
      collector.walk(syntax)

      for type in collector.types {
        resolved.insert(type + ": Sendable")
      }
    }

    return resolved
  }

  /// Extracts conformance and same-type relations from a where clause.
  private static func conditions(
    _ clause: GenericWhereClauseSyntax?
  ) -> [(String, String, String)] {

    (clause?.requirements ?? []).compactMap {
      switch $0.requirement {
      case .conformanceRequirement(let item): (item.leftType.trimmedDescription, ":", item.rightType.trimmedDescription)
      case .sameTypeRequirement(let item): (item.leftType.trimmedDescription, "==", item.rightType.trimmedDescription)
      default: nil
      }
    }
  }
}
