//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

/// Renders a resolved fake recipe with matching Debug and Release signatures.
enum PreviewableFakeFactoryBuilder {

  /// Renders the factory and any class convenience initializer from a validated recipe.
  /// - Parameters:
  ///   - recipe: The resolved initializer and ordered factory properties.
  ///   - isThrowing: Whether initialization or an eager nested default can throw.
  ///   - resolver: The default generator whose allocation state is retained across factories.
  /// - Throws: `GenerationError` when a property default cannot be generated.
  static func factory(
    recipe: ResolvedFake,
    isThrowing: Bool,
    resolver: inout DefaultValueResolver
  ) throws -> GeneratedFake {
    resolver.genericParameters = recipe.genericParameters
    defer { resolver.genericParameters = [] }
    let parameters = try factoryParameters(recipe: recipe, resolver: &resolver)
    let members = try debugMembers(recipe: recipe, parameters: parameters, isThrowing: isThrowing, resolver: resolver)

    return renderedFactory(recipe: recipe, parameters: parameters, members: members, isThrowing: isThrowing)
  }

  private static func factoryParameters(
    recipe: ResolvedFake,
    resolver: inout DefaultValueResolver
  ) throws -> (debug: [String], release: [String], arguments: [String]) {
    var parameters: [String] = []
    var releaseParameters: [String] = []
    var arguments: [String] = []
    let message = String(reflecting: "\(recipe.typeName).fake(...) is unavailable outside Debug builds")

    for property in recipe.properties {
      let name = property.escapedName
      resolver.fieldName = "\(recipe.typeName).\(property.name)"
      resolver.usedThrowingDefault = false
      let value = try resolver.defaultValue(for: property.type)
      let deferred = resolver.usedThrowingDefault
      let type = property.type.trimmedDescription
      let parameter = deferred ? "@autoclosure () throws -> \(type)" : try parameterType(property, resolver: resolver)
      parameters.append("\(name): \(parameter) = \(value)")
      releaseParameters.append(
        "\(name): \(parameter) = { () -> \(type) in preconditionFailure(\(message)) }()"
      )
      arguments.append("\(name): \(deferred ? "try \(name)()" : name)")
    }
    return (parameters, releaseParameters, arguments)
  }

  private static func debugMembers(
    recipe: ResolvedFake,
    parameters: (debug: [String], release: [String], arguments: [String]),
    isThrowing: Bool,
    resolver: DefaultValueResolver
  ) throws -> [String] {
    let effects = isThrowing ? " throws" : ""
    let initializerTry = recipe.initializerThrows ? "try " : ""
    let call =
      parameters.arguments.isEmpty
      ? "\(initializerTry).init()"
      : """
      \(initializerTry).init(
      \(parameters.arguments.joined(separator: ",\n").indented(by: 2))
      )
      """
    var members: [String] = []

    if recipe.convenienceInitializer {
      members.append(try convenienceInitializer(recipe: recipe, resolver: resolver))
    }
    let dateDocumentation =
      recipe.properties.contains { $0.type.trimmedDescription == "Date" }
      ? "/// Generated `Date` values begin at `2024-01-01T00:00:00Z` and advance by one day in source order.\n" : ""
    let throwsDocumentation =
      isThrowing ? "/// - Throws: Errors from initialization or nested fake construction.\n" : ""
    members.append(
      """
      /// Returns a fake with generated defaults or caller-provided values.
      \(dateDocumentation)\(throwsDocumentation)\(recipe.access)static func fake(
      \(parameters.debug.joined(separator: ",\n").indented(by: 2))
      )\(effects) -> \(recipe.returnType) {
      \(call.indented(by: 2))
      }
      """
    )
    return members
  }

  private static func convenienceInitializer(
    recipe: ResolvedFake,
    resolver: DefaultValueResolver
  ) throws -> String {
    let initializerEffects = recipe.initializerThrows ? " throws" : ""
    let initializerTry = recipe.initializerThrows ? "try " : ""
    let declarations = try recipe.properties.map {
      "\($0.escapedName): \(try parameterType($0, resolver: resolver))"
    }.joined(separator: ",\n")
    let assignments = recipe.properties.map { "self.\($0.escapedName) = \($0.escapedName)" }.joined(separator: "\n")
    return
      ("""
    \(recipe.access)convenience init(
    \(declarations.indented(by: 2))
    )\(initializerEffects) {
      \(initializerTry)self.init()
    \(assignments.indented(by: 2))
    }
    """)
  }

  private static func renderedFactory(
    recipe: ResolvedFake,
    parameters: (debug: [String], release: [String], arguments: [String]),
    members: [String],
    isThrowing: Bool
  ) -> GeneratedFake {
    let effects = isThrowing ? " throws" : ""
    let message = String(reflecting: "\(recipe.typeName).fake(...) is unavailable outside Debug builds")
    return GeneratedFake(
      debug: """
        extension \(recipe.typeName) {
        \(members.joined(separator: "\n\n").indented(by: 2))
        }
        """,
      release: """
        extension \(recipe.typeName) {
          /// Preserves the Debug factory signature for preview type checking.
          @inline(__always)
          \(recipe.access)static func fake(
        \(parameters.release.joined(separator: ",\n").indented(by: 4))
          )\(effects) -> \(recipe.returnType) {
            preconditionFailure(\(message))
          }
        }
        """
    )
  }

  /// Returns the parameter type, adding `@escaping` for a stored function value.
  /// - Parameters:
  ///   - property: The property supplied by the factory parameter.
  ///   - resolver: The resolver used to inspect aliased function types.
  /// - Throws: `GenerationError` for cyclic aliases.
  private static func parameterType(
    _ property: StoredProperty,
    resolver: DefaultValueResolver
  ) throws -> String {
    let type = property.type.trimmedDescription
    return try resolver.resolvedType(property.type).isFunctionType ? "@escaping \(type)" : type
  }
}
