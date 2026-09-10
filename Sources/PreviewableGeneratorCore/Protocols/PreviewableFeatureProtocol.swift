//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// What one Previewable macro provides for the generator to emit its declarations.
///
/// Adding a macro means adding a folder under `Features` whose generator conforms to this protocol, a case on
/// `PreviewableAnnotation`, and the matching arm in `PreviewableSourceGenerator`. The compiler refuses to build
/// until all three exist, which is why dispatch stays an exhaustive `switch` rather than a registry lookup.
protocol PreviewableFeatureProtocol: Sendable {

    /// The annotation this feature generates for.
    static var annotation: PreviewableAnnotation { get }

    /// Returns the first annotation that cannot coexist with an earlier one, or `nil` when the module is consistent.
    /// - Parameter annotations: Every annotated declaration in the module, in source order.
    static func conflict(in annotations: [AnnotatedDeclaration]) -> GenerationFailure?

    /// Generates the declarations one annotated declaration contributes.
    /// - Parameters:
    ///   - annotation: The annotated declaration to generate for.
    ///   - index: The module's declarations, used to read what the annotation refers to.
    ///   - resolver: The default-value resolver, whose accumulated state keeps generated values distinct.
    /// - Throws: `GenerationError` naming what the developer has to change.
    static func generate(
        from annotation: AnnotatedDeclaration,
        index: ModuleIndex,
        resolver: inout DefaultValueResolver
    ) throws -> GeneratedPreviewable
}
