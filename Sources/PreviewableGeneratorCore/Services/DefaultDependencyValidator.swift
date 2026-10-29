//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

/// Rejects eager default cycles before generated initializers can recurse or deadlock.
enum DefaultDependencyValidator {

  /// Validates that eager default construction has no dependency cycle.
  /// - Parameters:
  ///   - index: The resolved fake recipes and protocol declarations.
  ///   - sourceMap: The source locations used for validation failures.
  /// - Throws: A source diagnostic for cyclic aliases or defaults, or unsupported inherited requirements.
  static func validate(
    _ index: ModuleIndex,
    sourceMap: PreviewableSourceMap
  ) throws {
    let edges = try dependencyGraph(in: index, sourceMap: sourceMap)
    try validateCycles(in: edges, index: index, sourceMap: sourceMap)
  }
}

extension DefaultDependencyValidator {

  /// Records only eagerly constructed defaults so optional and deferred values do not create false cycles.
  private static func dependencyGraph(
    in index: ModuleIndex,
    sourceMap: PreviewableSourceMap
  ) throws -> [String: Set<String>] {
    var edges: [String: Set<String>] = [:]

    for annotation in index.annotations {
      let name = annotation.qualifiedName
      do {
        var resolver = DefaultValueResolver(index: index, context: .fake)
        let types: [TypeSyntax]

        if let fake = index.fakes[name] {
          resolver.genericParameters = fake.genericParameters
          types = fake.properties.map(\.type)
        } else if let declaration = annotation.declaration.as(ProtocolDeclSyntax.self) {
          var visited: Set<String> = []
          let members = try PreviewableRequirementFlattener.requirements(
            of: declaration,
            index: index,
            visited: &visited
          )
          resolver.genericParameters = Set(members.compactMap { $0.decl.as(AssociatedTypeDeclSyntax.self)?.name.text })
          types = members.flatMap(requirementTypes)
        } else {
          continue
        }
        edges[name] = Set(try types.flatMap { dependencies(try resolver.resolvedType($0), index: index) })
      } catch let error as GenerationError {
        throw sourceMap.diagnostic(error.message, for: annotation)
      }
    }
    return edges
  }

  private static func requirementTypes(
    in member: MemberBlockItemSyntax
  ) -> [TypeSyntax] {
    if let variable = member.decl.as(VariableDeclSyntax.self) {
      return variable.bindings.compactMap { $0.typeAnnotation?.type }
    }

    if let function = member.decl.as(FunctionDeclSyntax.self),
       function.genericParameterClause == nil,
       let type = function.signature.returnClause?.type {
      return [type]
    }
    return []
  }

  private static func validateCycles(
    in edges: [String: Set<String>],
    index: ModuleIndex,
    sourceMap: PreviewableSourceMap
  ) throws {
    var completed: Set<String> = []

    for name in edges.keys.sorted() {
      try walk(name, path: [], edges: edges, index: index, sourceMap: sourceMap, completed: &completed)
    }
  }

  private static func walk(
    _ name: String,
    path: [String],
    edges: [String: Set<String>],
    index: ModuleIndex,
    sourceMap: PreviewableSourceMap,
    completed: inout Set<String>
  ) throws {
    guard !completed.contains(name) else { return }
    if path.contains(name), let annotation = index.annotations.first(where: { $0.qualifiedName == name }) {
      throw sourceMap.diagnostic(
        "recursive default construction: \((path + [name]).joined(separator: " → "))",
        for: annotation
      )
    }

    for dependency in (edges[name] ?? []).sorted() {
      try walk(
        dependency,
        path: path + [name],
        edges: edges,
        index: index,
        sourceMap: sourceMap,
        completed: &completed
      )
    }
    completed.insert(name)
  }

  /// Returns only annotated types whose defaults must be constructed immediately.
  private static func dependencies(
    _ type: TypeSyntax,
    index: ModuleIndex
  ) -> [String] {
    switch type.as(TypeSyntaxEnum.self) {
    case .attributedType(let attributed):
      dependencies(attributed.baseType, index: index)
    case .optionalType, .implicitlyUnwrappedOptionalType, .functionType, .arrayType, .dictionaryType:
      []
    case .tupleType(let tuple):
      tupleDependencies(tuple, index: index)
    case .someOrAnyType(let existential):
      dependencies(existential.constraint, index: index)
    case .identifierType(let identifier):
      identifierDependencies(identifier, index: index)
    case .memberType(let member):
      memberDependencies(member, index: index)
    default:
      annotatedDependency(type.trimmedDescription, index: index)
    }
  }

  private static func tupleDependencies(
    _ tuple: TupleTypeSyntax,
    index: ModuleIndex
  ) -> [String] {
    tuple.elements.flatMap { dependencies($0.type, index: index) }
  }

  private static func identifierDependencies(
    _ identifier: IdentifierTypeSyntax,
    index: ModuleIndex
  ) -> [String] {
    let name = identifier.name.text

    guard !deferredContainers.contains(name) else { return [] }

    guard name == "Result", let success = resultSuccessType(in: identifier.genericArgumentClause)
    else { return annotatedDependency(identifier.trimmedDescription, index: index) }

    return dependencies(success, index: index)
  }

  private static func memberDependencies(
    _ member: MemberTypeSyntax,
    index: ModuleIndex
  ) -> [String] {
    guard member.baseType.trimmedDescription == "Swift", member.name.text == "Result",
          let success = resultSuccessType(in: member.genericArgumentClause) else {
      return annotatedDependency(member.trimmedDescription, index: index)
    }
    return dependencies(success, index: index)
  }

  private static func resultSuccessType(in arguments: GenericArgumentClauseSyntax?) -> TypeSyntax? {
    guard let first = arguments?.arguments.first else { return nil }
    return TypeSyntax(first.argument)
  }

  private static func annotatedDependency(
    _ name: String,
    index: ModuleIndex
  ) -> [String] {
    index.fakes[name] != nil || index.annotatedProtocols[name] != nil ? [name] : []
  }

  private static let deferredContainers: Set<String> = [
    "Optional", "Array", "Set", "Dictionary", "ContiguousArray"
  ]
}
