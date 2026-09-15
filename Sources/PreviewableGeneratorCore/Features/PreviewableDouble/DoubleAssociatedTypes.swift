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
  /// - Throws: For recursive associated-type bindings.
  init(
    declaration: ProtocolDeclSyntax, members: [MemberBlockItemSyntax], index: ModuleIndex, isolated: Bool
  ) throws {
    let associated = members.compactMap { $0.decl.as(AssociatedTypeDeclSyntax.self) }
    let names = Set(associated.map(\.name.text))
    let primary = declaration.primaryAssociatedTypeClause?.primaryAssociatedTypes.map(\.name.text) ?? []
    guard Set(primary).isSubset(of: names) else {
      throw GenerationError.message("@PreviewableDouble primary associated types must have associatedtype declarations")
    }
    let ordered = primary + names.subtracting(primary).sorted()
    var conditions: [(String, String, String)] = []
    for item in associated {
      for inherited in item.inheritanceClause?.inheritedTypes ?? [] {
        conditions.append((item.name.text, ":", inherited.type.trimmedDescription))
      }
      conditions += Self.conditions(item.genericWhereClause)
    }
    var visited: Set<String> = []
    func collectConstraints(_ protocolDeclaration: ProtocolDeclSyntax) {
      let name = index.protocols.first { $0.value.id == protocolDeclaration.id }?.key ?? protocolDeclaration.name.text
      guard visited.insert(name).inserted else { return }
      if let clause = protocolDeclaration.genericWhereClause {
        let qualifier = TypeNameResolver(
          index: index, scope: name.split(separator: ".").map(String.init),
          genericParameters: names)
        conditions += Self.conditions(qualifier.rewrite(clause).cast(GenericWhereClauseSyntax.self))
      }
      for inherited in protocolDeclaration.inheritanceClause?.inheritedTypes ?? [] {
        if let key = index.resolve(
          inherited.type.trimmedDescription, scope: name.split(separator: ".").map(String.init)),
          let base = index.protocols[key]
        {
          collectConstraints(base)
        }
      }
    }
    collectConstraints(declaration)
    var representatives = Dictionary(uniqueKeysWithValues: ordered.map { ($0, $0) })
    func representative(_ name: String) -> String {
      var current = name
      while let next = representatives[current], next != current { current = next }
      return current
    }
    // Unite associated names before applying concrete bindings so transitive equalities retain one identity.
    for (rawLeft, relation, rawRight) in conditions where relation == "==" {
      let left = rawLeft.replacingOccurrences(of: "Self.", with: "")
      let right = rawRight.replacingOccurrences(of: "Self.", with: "")
      if names.contains(left), names.contains(right) {
        let lhs = representative(left)
        let rhs = representative(right)
        let first = ordered.firstIndex(of: lhs)!
        let second = ordered.firstIndex(of: rhs)!
        representatives[first < second ? rhs : lhs] = first < second ? lhs : rhs
      }
    }
    var aliases: [String: String] = [:]
    for name in ordered where representative(name) != name { aliases[name] = representative(name) }
    let protocolName = index.protocols.first { $0.value.id == declaration.id }?.key ?? declaration.name.text
    let canonicalizer = DoubleTypeCanonicalizer(
      index: index, scope: protocolName.split(separator: ".").map(String.init))
    func bind(_ name: String, to expression: String) throws {
      let root = representative(name)
      if let existing = aliases[root], let previous = TypeSyntax.parsed(from: existing),
        let next = TypeSyntax.parsed(from: expression),
        try canonicalizer.canonical(previous) != canonicalizer.canonical(next)
      {
        throw GenerationError.message(
          "@PreviewableDouble associated type '\(name)' has incompatible same-type bindings")
      }
      aliases[root] = expression
    }
    for (rawLeft, relation, rawRight) in conditions where relation == "==" {
      let left = rawLeft.replacingOccurrences(of: "Self.", with: "")
      let right = rawRight.replacingOccurrences(of: "Self.", with: "")
      if names.contains(left), let type = TypeSyntax.parsed(from: right),
        names.isDisjoint(with: type.writtenTypeNames)
      {
        try bind(left, to: right)
      } else if names.contains(right), let type = TypeSyntax.parsed(from: left),
        names.isDisjoint(with: type.writtenTypeNames)
      {
        try bind(right, to: left)
      }
    }
    var generated: [String: String] = [:]
    var occupied = names
    for name in ordered where aliases[name] == nil {
      var parameter = "_Previewable" + name
      while occupied.contains(parameter) { parameter += "_" }
      occupied.insert(parameter)
      generated[name] = parameter
    }
    var resolving: Set<String> = []
    func resolve(_ name: String) throws -> String {
      if let value = generated[name] { return value }
      guard resolving.insert(name).inserted else {
        throw GenerationError.message("@PreviewableDouble associated type '\(name)' has a recursive same-type binding")
      }
      defer { resolving.remove(name) }
      guard let expression = aliases[name], let type = TypeSyntax.parsed(from: expression) else { return name }
      var replacements: [String: String] = [:]
      for dependency in Set(type.writtenTypeNames).intersection(names) {
        replacements[dependency] = try resolve(dependency)
      }
      let value = DoubleTypeSubstitution(replacements).rewrite(type).trimmedDescription
      generated[name] = value
      return value
    }
    for name in ordered { _ = try resolve(name) }
    bindings = generated
    parameters = ordered.filter { aliases[$0] == nil }.compactMap { generated[$0] }
    let rewriter = DoubleTypeSubstitution(generated)
    let generics = Set(parameters)
    var resolved: Set<String> = []
    for (left, relation, right) in conditions {
      guard let leftType = TypeSyntax.parsed(from: left), let rightType = TypeSyntax.parsed(from: right) else {
        continue
      }
      let lhs = rewriter.rewrite(leftType).cast(TypeSyntax.self)
      let rhs = rewriter.rewrite(rightType).cast(TypeSyntax.self)
      if relation == "==", lhs.trimmedDescription == rhs.trimmedDescription { continue }
      if !generics.isDisjoint(with: lhs.writtenTypeNames + rhs.writtenTypeNames) {
        resolved.insert(lhs.trimmedDescription + " " + relation + " " + rhs.trimmedDescription)
      }
    }
    // Shared recordings and responses require sendable components, unlike actor-local values.
    for member in members {
      let syntax = rewriter.rewrite(member)
      let function = syntax.as(MemberBlockItemSyntax.self)?.decl.as(FunctionDeclSyntax.self)
      let variable = syntax.as(MemberBlockItemSyntax.self)?.decl.as(VariableDeclSyntax.self)
      let subscriptDeclaration = syntax.as(MemberBlockItemSyntax.self)?.decl.as(SubscriptDeclSyntax.self)
      let attributes = function?.attributes ?? variable?.attributes ?? subscriptDeclaration?.attributes ?? []
      let modifiers = function?.modifiers ?? variable?.modifiers ?? subscriptDeclaration?.modifiers ?? []
      let nonisolated = modifiers.contains { $0.name.text == "nonisolated" }
      if !nonisolated && (isolated || !DoubleStorageBuilder.isolationAttributes(in: attributes, index: index).isEmpty) {
        continue
      }
      if function == nil && variable == nil && subscriptDeclaration == nil { continue }
      let collector = AssociatedSendableCollector(parameters: generics)
      collector.walk(syntax)
      for type in collector.types { resolved.insert(type + ": Sendable") }
    }
    constraints = resolved.sorted()
  }

  /// Renders explicit aliases without relying on associated-type inference.
  /// - Parameter access: The declaration's effective access prefix.
  func aliases(access: String) -> String {
    bindings.keys.sorted().map { "\(access)typealias \($0) = \(bindings[$0]!)" }.joined(separator: "\n")
  }

  /// Extracts conformance and same-type relations from a where clause.
  private static func conditions(_ clause: GenericWhereClauseSyntax?) -> [(String, String, String)] {
    (clause?.requirements ?? []).compactMap {
      switch $0.requirement {
      case .conformanceRequirement(let item):
        return (item.leftType.trimmedDescription, ":", item.rightType.trimmedDescription)
      case .sameTypeRequirement(let item):
        return (item.leftType.trimmedDescription, "==", item.rightType.trimmedDescription)
      default: return nil
      }
    }
  }
}

/// Collects associated components that may cross a nonisolated storage boundary.
private final class AssociatedSendableCollector: SyntaxVisitor {
  let parameters: Set<String>
  var types: Set<String> = []

  /// Creates a collector for the generated generic parameter names.
  /// - Parameter parameters: The double's free associated-type parameters.
  init(parameters: Set<String>) {
    self.parameters = parameters
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
    if !parameters.isDisjoint(with: TypeSyntax(node).writtenTypeNames) {
      types.insert(node.trimmedDescription)
      return .skipChildren
    }
    return .visitChildren
  }

  override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
    if parameters.contains(node.name.text) { types.insert(node.name.text) }
    return .visitChildren
  }
}
