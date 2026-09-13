import SwiftSyntax

/// Rejects eager default cycles before generated initializers can recurse or deadlock.
enum DefaultDependencyValidator {

  /// Validates that eager default construction has no dependency cycle.
  /// - Parameters:
  ///   - index: The resolved fake recipes and protocol declarations.
  ///   - sourceMap: The source locations used for validation failures.
  /// - Throws: A source diagnostic for cyclic defaults or unreadable inherited requirements.
  static func validate(_ index: ModuleIndex, sourceMap: PreviewableSourceMap) throws {
    var edges: [String: Set<String>] = [:]
    for annotation in index.annotations {
      let name = annotation.qualifiedName
      if let fake = index.fakes[name] {
        edges[name] = Set(fake.properties.flatMap { dependencies($0.type, index: index) })
      } else if let declaration = annotation.declaration.as(ProtocolDeclSyntax.self) {
        var visited: Set<String> = []
        let members: [MemberBlockItemSyntax]
        do {
          members = try PreviewableRequirementFlattener.requirements(of: declaration, index: index, visited: &visited)
        } catch let error as GenerationError {
          throw sourceMap.diagnostic(error.message, for: annotation)
        }
        let rewriter = TypeNameResolver(index: index, scope: name.split(separator: ".").map(String.init))
        edges[name] = Set(
          members.flatMap { member -> [String] in
            if let variable = member.decl.as(VariableDeclSyntax.self) {
              return variable.bindings.flatMap { binding -> [String] in
                guard let type = binding.typeAnnotation?.type else { return [] }
                return dependencies(rewriter.rewrite(type).cast(TypeSyntax.self), index: index)
              }
            }
            if let function = member.decl.as(FunctionDeclSyntax.self), function.genericParameterClause == nil,
              let type = function.signature.returnClause?.type
            {
              return dependencies(rewriter.rewrite(type).cast(TypeSyntax.self), index: index)
            }
            return []
          })
      }
    }
    var completed: Set<String> = []
    func walk(_ name: String, path: [String]) throws {
      guard !completed.contains(name) else { return }
      if path.contains(name), let annotation = index.annotations.first(where: { $0.qualifiedName == name }) {
        throw sourceMap.diagnostic(
          "recursive default construction: \((path + [name]).joined(separator: " → "))",
          for: annotation)
      }
      for dependency in (edges[name] ?? []).sorted() { try walk(dependency, path: path + [name]) }
      completed.insert(name)
    }
    for name in edges.keys.sorted() { try walk(name, path: []) }
  }

  /// Returns annotated types constructed eagerly by the supplied type's default.
  /// - Parameters:
  ///   - type: The qualified type to inspect.
  ///   - index: The available fake recipes and annotated protocols.
  private static func dependencies(_ type: TypeSyntax, index: ModuleIndex) -> [String] {
    if let attributed = type.as(AttributedTypeSyntax.self) { return dependencies(attributed.baseType, index: index) }
    if type.isOptional || type.isFunctionType || type.is(ArrayTypeSyntax.self) || type.is(DictionaryTypeSyntax.self) {
      return []
    }
    if let tuple = type.as(TupleTypeSyntax.self) {
      return tuple.elements.flatMap { dependencies($0.type, index: index) }
    }
    if let existential = type.as(SomeOrAnyTypeSyntax.self) { return dependencies(existential.constraint, index: index) }
    if let identifier = type.as(IdentifierTypeSyntax.self),
      ["Optional", "Array", "Set", "Dictionary", "ContiguousArray"].contains(identifier.name.text)
    {
      return []
    }
    if let identifier = type.as(IdentifierTypeSyntax.self), identifier.name.text == "Result",
      let first = identifier.genericArgumentClause?.arguments.first,
      let success = TypeSyntax(first.argument)
    {
      return dependencies(success, index: index)
    }
    if let member = type.as(MemberTypeSyntax.self), member.baseType.trimmedDescription == "Swift",
      member.name.text == "Result", let first = member.genericArgumentClause?.arguments.first,
      let success = TypeSyntax(first.argument)
    {
      return dependencies(success, index: index)
    }
    let name = type.trimmedDescription
    return index.fakes[name] != nil || index.annotatedProtocols[name] != nil ? [name] : []
  }
}
