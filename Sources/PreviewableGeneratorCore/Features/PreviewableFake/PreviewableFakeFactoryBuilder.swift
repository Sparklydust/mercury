//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Builds the `fake(...)` factory emitted for Debug builds and the trapping stub emitted for every other.
enum PreviewableFakeFactoryBuilder {

  /// Emits the Debug factory and its unavailable counterpart for an already-resolved parameter list.
  static func factory(
    typeName: String,
    returnType: String,
    access: String,
    properties: [StoredProperty],
    genericParameters: Set<String>,
    declaresConvenienceInitializer: Bool,
    resolver: inout DefaultValueResolver
  ) throws -> GeneratedFake {
    resolver.genericParameters = genericParameters
    var parameterDeclarations: [String] = []
    for property in properties {
      let printedType = property.type.trimmedDescription
      // A generic-typed property has no correct default, so the caller must supply it.
      if genericParameters.contains(printedType) {
        parameterDeclarations.append("\(property.name): \(printedType)")
        continue
      }
      let defaultValue = try resolver.defaultValue(for: property.type)
      parameterDeclarations.append("\(property.name): \(parameterType(of: property)) = \(defaultValue)")
    }
    resolver.genericParameters = []

    let parameters = parameterDeclarations.joined(separator: ",\n")
    let values = properties.enumerated().map { offset, property in
      let comma = offset == properties.count - 1 ? String() : ","
      return "  \(property.name): \(property.name)\(comma)"
    }
    let body = ([".init("] + values + [")"]).joined(separator: "\n")
    let dateDocumentation = properties.contains {
      $0.type.trimmedDescription == "Date"
    }
    ? """
        ///
        /// Generated `Date` values begin at `2024-01-01T00:00:00Z` and advance by one day in source order.
        """
    : String()

    let method = """
      /// Returns a fake `\(typeName)` with generated defaults or caller-provided stored-property values.
      \(dateDocumentation)
      \(access)static func fake(
      \(parameters.indented(by: 2))
      ) -> \(returnType) {
      \(body.indented(by: 2))
      }
      """
    var extensionMembers: [String] = []
    if declaresConvenienceInitializer {
      let initializerParameters = properties.map {
        "\($0.name): \(parameterType(of: $0))"
      }.joined(separator: ",\n")
      let assignments = properties.map {
        "self.\($0.name) = \($0.name)"
      }.joined(separator: "\n")
      extensionMembers.append(
        """
        \(access)convenience init(
        \(initializerParameters.indented(by: 2))
        ) {
          self.init()
        \(assignments.indented(by: 2))
        }
        """
      )
    }
    extensionMembers.append(method)
    let extensionBody = extensionMembers.map {
      $0.indented(by: 2)
    }.joined(separator: "\n\n")
    let debug = """
      /// Provides a fake factory for Debug builds, test targets, and SwiftUI previews.
      extension \(typeName) {
      \(extensionBody)
      }
      """
    return GeneratedFake(
      debug: debug,
      release: releaseFactory(
        typeName: typeName,
        returnType: returnType,
        access: access,
        properties: properties,
        genericParameters: genericParameters
      )
    )
  }

  private static func releaseFactory(
    typeName: String,
    returnType: String,
    access: String,
    properties: [StoredProperty],
    genericParameters: Set<String>
  ) -> String {
    let message = String(
      reflecting: "\(typeName).fake(...) is unavailable outside Debug builds and SwiftUI previews"
    )
    let parameters = properties.map { property in
      let printedType = property.type.trimmedDescription
      guard !genericParameters.contains(printedType) else {
        return "\(property.name): \(printedType)"
      }
      let declaredType = parameterType(of: property)
      return "\(property.name): \(declaredType) = { () -> \(printedType) in preconditionFailure(\(message)) }()"
    }.joined(separator: ",\n")
    return """
      /// Preserves the `fake(...)` signature outside Debug builds.
      extension \(typeName) {
        /// Prevents fake construction outside Debug builds.
        /// - Warning: Available only in Debug builds.
        @inline(__always)
        \(access)static func fake(
      \(parameters.indented(by: 4))
        ) -> \(returnType) {
          preconditionFailure(\(message))
        }
      }
      """
  }

  /// Returns the parameter type as the factory must write it.
  ///
  /// A parameter is non-escaping by default, so a closure passed straight into the type's initializer — which
  /// stores it — would not compile. Marking a function type `@escaping` is what lets a fake carry a callback.
  private static func parameterType(of property: StoredProperty) -> String {
    let printedType = property.type.trimmedDescription
    guard property.type.isFunctionType else { return printedType }
    return "@escaping \(printedType)"
  }
}
