//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftParser
import SwiftSyntax

/// Generates derived Swift source for declarations annotated with Previewable macros.
public enum PreviewableSourceGenerator {

    /// The features generation dispatches over, in the order their declarations are emitted.
    ///
    /// The order is what fixes the shape of the generated file: every double precedes every fake, whatever order the
    /// annotations appear in the module.
    private static let features: [any PreviewableFeatureProtocol.Type] = [
        PreviewableDoubleGenerator.self,
        PreviewableFakeGenerator.self
    ]

    /// Generates the doubles, fake factories, and preview accessors declared by the supplied source files.
    /// - Parameter files: The module's Swift source files, with the paths reported in diagnostics.
    /// - Returns: A compilable Swift source file containing the generated declarations.
    /// - Throws: `PreviewableDiagnostic` naming the declaration that must change.
    public static func generate(from files: [PreviewableSourceFile]) throws -> String {
        let trees = files.map { Parser.parse(source: $0.text) }
        let sourceMap = PreviewableSourceMap(files: files, trees: trees)
        let index = moduleIndex(of: trees)

        try PreviewableAnnotationValidator.validate(index, features: features, sourceMap: sourceMap)

        // One resolver per feature, kept for the whole run: its accumulated state is what keeps generated
        // values distinct, so replacing or copying it mid-run would repeat them.
        var doubleResolver = DefaultValueResolver(index: index, context: .double)
        var fakeResolver = DefaultValueResolver(index: index, context: .fake)
        var sections: [PreviewableAnnotation: GeneratedPreviewable] = [:]

        for annotation in index.annotations {
            do {
                let generated: GeneratedPreviewable
                switch annotation.annotation {
                case .double:
                    generated = try PreviewableDoubleGenerator.generate(
                        from: annotation,
                        index: index,
                        resolver: &doubleResolver
                    )
                case .fake:
                    generated = try PreviewableFakeGenerator.generate(
                        from: annotation,
                        index: index,
                        resolver: &fakeResolver
                    )
                }
                sections[annotation.annotation, default: GeneratedPreviewable()]
                    += sourceMap.attributed(generated, to: annotation)
            } catch let error as GenerationError {
                throw sourceMap.diagnostic(error.message, for: annotation)
            }
        }

        return PreviewableSourceAssembler.assemble(
            sections: features.compactMap { sections[$0.annotation] },
            trees: trees,
            index: index
        )
    }

    /// Generates from raw source texts, without file paths.
    /// - Parameter sources: The complete Swift source texts to parse together.
    /// - Returns: A compilable Swift source file containing the generated declarations.
    /// - Throws: `PreviewableDiagnostic` naming the declaration that must change.
    public static func generate(from sources: [String]) throws -> String {
        try generate(
            from: sources.enumerated().map {
                PreviewableSourceFile(path: "<source \($0.offset)>", text: $0.element)
            }
        )
    }

    /// Indexes every declaration in the module, so an annotation can be read against what surrounds it.
    private static func moduleIndex(of trees: [SourceFileSyntax]) -> ModuleIndex {
        var index = ModuleIndex()
        for (offset, tree) in trees.enumerated() {
            let collector = DeclarationCollector(fileIndex: offset)
            collector.walk(tree)
            index.merge(collector.index)
        }
        return index
    }
}
