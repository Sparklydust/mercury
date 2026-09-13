//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Everything the generator knows about the module being compiled.
///
/// The generator only ever sees one module's sources, so this index is what separates "declared here and
/// therefore checkable" from "declared elsewhere and therefore taken on trust".
struct ModuleIndex {

  /// Protocol declarations keyed by qualified name.
  var protocols: [String: ProtocolDeclSyntax] = [:]
  /// Qualified names of protocols annotated with `@PreviewableDouble`.
  var annotatedProtocols: [String: String] = [:]
  /// Every nominal type declared in the module, by qualified name.
  var declaredTypes: Set<String> = []
  /// The declared visibility of every nominal type, by qualified name.
  var typeAccess: [String: AccessLevel] = [:]

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
  func resolve(_ name: String, scope: [String]) -> String? {
    for count in stride(from: scope.count, through: 0, by: -1) {
      let candidate = (Array(scope.prefix(count)) + [name]).joined(separator: ".")
      if declaredTypes.contains(candidate) || protocols[candidate] != nil || fakeAnnotatedTypes.contains(candidate) {
        return candidate
      }
    }
    return nil
  }
  /// Returns whether the module declares the supplied type name.
  func declaresType(_ name: String) -> Bool {
    declaredTypes.contains(name)
  }

  /// Folds the declarations found in one file into the module-wide index.
  mutating func merge(_ other: ModuleIndex) {
    protocols.merge(other.protocols) { current, _ in current }
    annotatedProtocols.merge(other.annotatedProtocols) { current, _ in current }
    enumDefaults.merge(other.enumDefaults) { current, _ in current }
    typeAccess.merge(other.typeAccess) { current, _ in current }
    declaredTypes.formUnion(other.declaredTypes)
    genericTypes.formUnion(other.genericTypes)
    fakeAnnotatedTypes.formUnion(other.fakeAnnotatedTypes)
    globalActors.formUnion(other.globalActors)
    annotations.append(contentsOf: other.annotations)
  }
}
