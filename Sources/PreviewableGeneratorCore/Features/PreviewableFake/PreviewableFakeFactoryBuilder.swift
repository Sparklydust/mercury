import SwiftSyntax

/// Renders a resolved fake recipe with matching Debug and Release signatures.
enum PreviewableFakeFactoryBuilder {
  static func factory(
    recipe: ResolvedFake,
    isThrowing: Bool,
    resolver: inout DefaultValueResolver
  ) throws -> GeneratedFake {
    resolver.genericParameters = recipe.genericParameters
    defer { resolver.genericParameters = [] }
    var parameters: [String] = []
    var releaseParameters: [String] = []
    var arguments: [String] = []
    let message = String(reflecting: "\(recipe.typeName).fake(...) is unavailable outside Debug builds")
    for property in recipe.properties {
      resolver.fieldName = "\(recipe.typeName).\(property.name)"
      resolver.usedThrowingDefault = false
      let value = try resolver.defaultValue(for: property.type)
      let deferred = resolver.usedThrowingDefault
      let type = property.type.trimmedDescription
      let parameter = deferred ? "@autoclosure () throws -> \(type)" : parameterType(property)
      parameters.append("\(property.name): \(parameter) = \(value)")
      releaseParameters.append(
        "\(property.name): \(parameter) = { () -> \(type) in preconditionFailure(\(message)) }()"
      )
      arguments.append("\(property.name): \(deferred ? "try \(property.name)()" : property.name)")
    }
    let effects = isThrowing ? " throws" : ""
    let initializerEffects = recipe.initializerThrows ? " throws" : ""
    let initializerTry = recipe.initializerThrows ? "try " : ""
    let call =
      arguments.isEmpty
      ? "\(initializerTry).init()"
      : """
      \(initializerTry).init(
      \(arguments.joined(separator: ",\n").indented(by: 2))
      )
      """
    var members: [String] = []
    if recipe.convenienceInitializer {
      let declarations = recipe.properties.map { "\($0.name): \(parameterType($0))" }.joined(separator: ",\n")
      let assignments = recipe.properties.map { "self.\($0.name) = \($0.name)" }.joined(separator: "\n")
      members.append(
        """
        \(recipe.access)convenience init(
        \(declarations.indented(by: 2))
        )\(initializerEffects) {
          \(initializerTry)self.init()
        \(assignments.indented(by: 2))
        }
        """)
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
      \(parameters.joined(separator: ",\n").indented(by: 2))
      )\(effects) -> \(recipe.returnType) {
      \(call.indented(by: 2))
      }
      """)
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
        \(releaseParameters.joined(separator: ",\n").indented(by: 4))
          )\(effects) -> \(recipe.returnType) {
            preconditionFailure(\(message))
          }
        }
        """
    )
  }

  private static func parameterType(_ property: StoredProperty) -> String {
    let type = property.type.trimmedDescription
    return property.type.isFunctionType ? "@escaping \(type)" : type
  }
}
