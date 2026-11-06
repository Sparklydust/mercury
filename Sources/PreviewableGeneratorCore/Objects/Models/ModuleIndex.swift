//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

/// The declarations, annotations, and resolved factories available within one compilation module.
///
/// Declarations from imported modules are not indexed.
struct ModuleIndex {

  /// Protocol declarations keyed by qualified name.
  var protocols: [String: ProtocolDeclSyntax] = [:]
  /// Qualified names of protocols annotated with `@PreviewableDouble`.
  var annotatedProtocols: [String: String] = [:]
  /// Every nominal type declared in the module, by qualified name.
  var declaredTypes: Set<String> = []
  /// The effective visibility of indexed types, protocols, and aliases, including enclosing types.
  var typeAccess: [String: AccessLevel] = [:]
  /// Nongeneric typealias targets keyed by qualified declaration name.
  var typeAliases: [String: TypeSyntax] = [:]
  /// File-scope names that cannot coexist with a generated type or property.
  var globalNames: Set<String> = []

  /// Nominal types declared with generic parameters, by qualified name.
  var genericTypes: Set<String> = []
  /// Types annotated with `@PreviewableFake`, by qualified name.
  var fakeAnnotatedTypes: Set<String> = []
  /// The first parameterless case of each enumeration, keyed by qualified name.
  var enumDefaults: [String: String] = [:]
  /// Every annotated declaration found anywhere in the module.
  var annotations: [AnnotatedDeclaration] = []
  /// Resolved fake construction recipes, keyed by qualified type name.
  var fakes: [String: ResolvedFake] = [:]
  /// Factories whose initializer or a required nested default can throw.
  var throwingFakes: Set<String> = []
  /// Global actor declarations available for resolving protocol isolation.
  var globalActors: Set<String> = []

  /// Resolves a written name from its innermost lexical scope outward.
  /// - Parameters:
  ///   - name: The written type or protocol name to resolve.
  ///   - scope: Enclosing type names ordered from outermost to innermost.
  /// - Returns: The first indexed qualified name, or `nil` if no candidate is indexed.
  func resolve(
    _ name: String,
    scope: [String]
  ) -> String? {
    for count in stride(from: scope.count, through: 0, by: -1) {
      let candidate = (Array(scope.prefix(count)) + [name]).joined(separator: ".")

      if declaredTypes.contains(candidate)
         || protocols[candidate] != nil
         || fakeAnnotatedTypes.contains(candidate)
         || typeAliases[candidate] != nil {
        return candidate
      }
    }
    return nil
  }

  /// Returns the emitted access prefix after accounting for enclosing type visibility.
  /// - Parameter name: The qualified declaration name.
  func accessPrefix(for name: String) -> String {
    let access = typeAccess[name] ?? .internal
    return access == .internal ? "" : access.keyword + " "
  }

  /// Returns whether the module declares the supplied type name.
  func declaresType(_ name: String) -> Bool {
    declaredTypes.contains(name)
  }

  /// Folds the declarations found in one file into the module-wide index.
  /// - Parameter other: Collected declarations to append; existing keyed entries take precedence.
  mutating func merge(_ other: ModuleIndex) {
    protocols.merge(other.protocols) { current, _ in current }
    annotatedProtocols.merge(other.annotatedProtocols) { current, _ in current }
    enumDefaults.merge(other.enumDefaults) { current, _ in current }
    typeAccess.merge(other.typeAccess) { current, _ in current }
    typeAliases.merge(other.typeAliases) { current, _ in current }
    globalNames.formUnion(other.globalNames)
    declaredTypes.formUnion(other.declaredTypes)
    genericTypes.formUnion(other.genericTypes)
    fakeAnnotatedTypes.formUnion(other.fakeAnnotatedTypes)
    globalActors.formUnion(other.globalActors)
    annotations.append(contentsOf: other.annotations)
  }
}
