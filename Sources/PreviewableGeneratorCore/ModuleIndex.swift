//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Everything the generator knows about the module being compiled.
///
/// The generator only ever sees one module's sources, so this index is what separates "declared here and
/// therefore checkable" from "declared elsewhere and therefore taken on trust".
struct ModuleIndex {

    /// Protocol declarations, reachable by both simple and qualified name.
    var protocols: [String: ProtocolDeclSyntax] = [:]

    /// Qualified names of protocols annotated with `@PreviewableDouble`, by simple name.
    var annotatedProtocols: [String: String] = [:]

    /// Every nominal type declared in the module, by simple and qualified name.
    var declaredTypes: Set<String> = []

    /// Nominal types declared with generic parameters, by simple and qualified name.
    var genericTypes: Set<String> = []

    /// Types annotated with `@PreviewableFake`, by simple and qualified name.
    var fakeAnnotatedTypes: Set<String> = []

    /// The first parameterless case of each enumeration, keyed by simple and qualified name.
    var enumDefaults: [String: String] = [:]

    /// Every annotated declaration found anywhere in the module.
    var annotations: [AnnotatedDeclaration] = []

    /// Returns whether the module declares the supplied type name.
    func declaresType(_ name: String) -> Bool {
        declaredTypes.contains(name)
    }

    /// Folds the declarations found in one file into the module-wide index.
    mutating func merge(_ other: ModuleIndex) {
        protocols.merge(other.protocols) { current, _ in current }
        annotatedProtocols.merge(other.annotatedProtocols) { current, _ in current }
        enumDefaults.merge(other.enumDefaults) { current, _ in current }
        declaredTypes.formUnion(other.declaredTypes)
        genericTypes.formUnion(other.genericTypes)
        fakeAnnotatedTypes.formUnion(other.fakeAnnotatedTypes)
        annotations.append(contentsOf: other.annotations)
    }
}
