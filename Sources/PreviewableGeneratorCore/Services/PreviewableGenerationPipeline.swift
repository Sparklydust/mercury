//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftParser
import SwiftSyntax

/// Coordinates one generation run without exposing implementation state to consumers.
enum PreviewableGenerationPipeline {

  /// The features generation dispatches over, in the order their declarations are emitted.
  ///
  /// The order is what fixes the shape of the generated file: every double precedes every fake, whatever order the
  /// annotations appear in the module.
  private static let features: [any PreviewableFeatureProtocol.Type] = [
    PreviewableDoubleGenerator.self,
    PreviewableFakeGenerator.self
  ]

  static func generate(from files: [PreviewableSourceFile]) throws -> String {
    let files = files.sorted { $0.path < $1.path }
    let trees = files.map { Parser.parse(source: $0.text) }
    let sourceMap = PreviewableSourceMap(files: files, trees: trees)
    let index = try resolvedIndex(of: trees, sourceMap: sourceMap)

    return try render(index: index, trees: trees, sourceMap: sourceMap)
  }
}

private extension PreviewableGenerationPipeline {

  static func resolvedIndex(
    of trees: [SourceFileSyntax],
    sourceMap: PreviewableSourceMap
  ) throws -> ModuleIndex {
    var index = moduleIndex(of: trees)
    try PreviewableAnnotationValidator.validate(index, features: features, sourceMap: sourceMap)
    try resolveFakes(in: &index, sourceMap: sourceMap)
    try DefaultDependencyValidator.validate(index, sourceMap: sourceMap)
    return index
  }

  static func resolveFakes(
    in index: inout ModuleIndex,
    sourceMap: PreviewableSourceMap
  ) throws {
    for annotation in index.annotations where annotation.annotation == .fake {
      do {
        index.fakes[annotation.qualifiedName] = try FakeDeclarationResolver.resolve(annotation, index: index)
      } catch let error as GenerationError {
        throw sourceMap.diagnostic(error.message, for: annotation)
      }
    }
    try propagateThrowingDefaults(in: &index, sourceMap: sourceMap)
  }

  static func propagateThrowingDefaults(
    in index: inout ModuleIndex,
    sourceMap: PreviewableSourceMap
  ) throws {
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
            if resolver.usedThrowingDefault, index.throwingFakes.insert(recipe.typeName).inserted {
              changed = true
            }
          }
        } catch let error as GenerationError {
          throw sourceMap.diagnostic(error.message, for: recipe.annotation)
        }
      }
    }
  }

  static func render(
    index: ModuleIndex,
    trees: [SourceFileSyntax],
    sourceMap: PreviewableSourceMap
  ) throws -> String {
    // One resolver per feature, kept for the whole run: its accumulated state is what keeps generated
    // values distinct, so replacing or copying it mid-run would repeat them.
    var doubleResolver = DefaultValueResolver(index: index, context: .double)
    var fakeResolver = DefaultValueResolver(index: index, context: .fake)
    var sections: [PreviewableAnnotation: GeneratedPreviewable] = [:]
    var generatedNames: Set<String> = []

    for annotation in index.annotations {
      do {
        let generated = try generate(
          annotation,
          index: index,
          doubleResolver: &doubleResolver,
          fakeResolver: &fakeResolver
        )
        try validateNames(in: generated, for: annotation, index: index, seen: &generatedNames)
        sections[annotation.annotation, default: GeneratedPreviewable()] += sourceMap.attributed(
          generated,
          to: annotation
        )
      } catch let error as GenerationError {
        throw sourceMap.diagnostic(error.message, for: annotation)
      }
    }

    return PreviewableSourceAssembler.assemble(
      sections: features.compactMap { sections[$0.annotation] },
      trees: trees
    )
  }

  static func generate(
    _ annotation: AnnotatedDeclaration,
    index: ModuleIndex,
    doubleResolver: inout DefaultValueResolver,
    fakeResolver: inout DefaultValueResolver
  ) throws -> GeneratedPreviewable {
    switch annotation.annotation {
    case .double:
      try PreviewableDoubleGenerator.generate(
        from: annotation,
        index: index,
        resolver: &doubleResolver
      )
    case .fake:
      try PreviewableFakeGenerator.generate(
        from: annotation,
        index: index,
        resolver: &fakeResolver
      )
    }
  }

  static func validateNames(
    in generated: GeneratedPreviewable,
    for annotation: AnnotatedDeclaration,
    index: ModuleIndex,
    seen: inout Set<String>
  ) throws {
    for name in generated.globalNames {
      guard !index.globalNames.contains(name), seen.insert(name).inserted else {
        throw GenerationError.message(
          "@\(annotation.annotation.rawValue) generated name '\(name)' conflicts with another declaration — rename it"
        )
      }
    }
  }

  /// Indexes every declaration in the module, so an annotation can be read against what surrounds it.
  static func moduleIndex(of trees: [SourceFileSyntax]) -> ModuleIndex {
    var index = ModuleIndex()

    for (offset, tree) in trees.enumerated() {
      let collector = DeclarationCollector(fileIndex: offset)
      collector.walk(tree)
      index.merge(collector.index)
    }

    return index
  }
}
