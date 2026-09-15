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
    PreviewableFakeGenerator.self,
  ]

  /// Generates the doubles, fake factories, and preview accessors declared by the supplied source files.
  /// - Parameter files: The module's Swift source files, with the paths reported in diagnostics.
  /// - Returns: A compilable Swift source file containing the generated declarations.
  /// - Throws: `PreviewableDiagnostic` naming the declaration that must change.
  public static func generate(from files: [PreviewableSourceFile]) throws -> String {
    let files = files.sorted { $0.path < $1.path }
    let trees = files.map { Parser.parse(source: $0.text) }
    let sourceMap = PreviewableSourceMap(files: files, trees: trees)
    var index = moduleIndex(of: trees)

    try PreviewableAnnotationValidator.validate(index, features: features, sourceMap: sourceMap)
    for annotation in index.annotations where annotation.annotation == .fake {
      do {
        index.fakes[annotation.qualifiedName] = try FakeDeclarationResolver.resolve(annotation, index: index)
      } catch let error as GenerationError {
        throw sourceMap.diagnostic(error.message, for: annotation)
      }
    }
    index.throwingFakes = Set(index.fakes.values.filter(\.initializerThrows).map(\.typeName))
    // Resolve repeatedly until throwing effects have propagated through every dependency.
    var changed = true
    while changed {
      changed = false
      for recipe in index.annotations.compactMap({ index.fakes[$0.qualifiedName] }) {
        var resolver = DefaultValueResolver(index: index, context: .fake)
        resolver.genericParameters = recipe.genericParameters
        do {
          for property in recipe.properties {
            resolver.fieldName = "\(recipe.typeName).\(property.name)"
            resolver.usedThrowingDefault = false
            _ = try resolver.defaultValue(for: property.type)
            if resolver.usedThrowingDefault, index.throwingFakes.insert(recipe.typeName).inserted { changed = true }
          }
        } catch let error as GenerationError {
          throw sourceMap.diagnostic(error.message, for: recipe.annotation)
        }
      }
    }
    try DefaultDependencyValidator.validate(index, sourceMap: sourceMap)

    // One resolver per feature, kept for the whole run: its accumulated state is what keeps generated
    // values distinct, so replacing or copying it mid-run would repeat them.
    var doubleResolver = DefaultValueResolver(index: index, context: .double)
    var fakeResolver = DefaultValueResolver(index: index, context: .fake)
    var sections: [PreviewableAnnotation: GeneratedPreviewable] = [:]
    var generatedNames: Set<String> = []

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
        for name in generated.globalNames {
          guard !index.globalNames.contains(name), generatedNames.insert(name).inserted else {
            throw GenerationError.message(
              "@\(annotation.annotation.rawValue) generated name '\(name)' conflicts with another declaration — rename it"
            )
          }
        }
        sections[annotation.annotation, default: GeneratedPreviewable()] += sourceMap.attributed(
          generated, to: annotation)
      } catch let error as GenerationError {
        throw sourceMap.diagnostic(error.message, for: annotation)
      }
    }

    return PreviewableSourceAssembler.assemble(
      sections: features.compactMap { sections[$0.annotation] },
      trees: trees
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
