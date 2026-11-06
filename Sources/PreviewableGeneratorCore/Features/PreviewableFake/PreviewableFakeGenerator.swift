//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

/// Generates the fake factory `@PreviewableFake` derives from a type declared in this module.
enum PreviewableFakeGenerator: PreviewableFeatureProtocol {

  static let annotation: PreviewableAnnotation = .fake

  static func conflict(in annotations: [AnnotatedDeclaration]) -> GenerationFailure? {
    // An owned type carries one annotation at most, but an extension can be annotated in any number of files.
    var fakedTypes: Set<String> = []

    for annotation in annotations where annotation.annotation == .fake {
      guard !fakedTypes.insert(annotation.qualifiedName).inserted else { continue }
      return GenerationFailure(
        annotation: annotation,
        message: """
          '\(annotation.qualifiedName)' is annotated with @PreviewableFake more than once \
          — keep a single annotation
          """
      )
    }
    return .none
  }

  static func generate(
    from annotation: AnnotatedDeclaration,
    index: ModuleIndex,
    resolver: inout DefaultValueResolver
  ) throws -> GeneratedPreviewable {
    guard let recipe = index.fakes[annotation.qualifiedName] else {
      throw GenerationError.message("missing resolved fake for '\(annotation.qualifiedName)'")
    }
    let generated = try PreviewableFakeFactoryBuilder.factory(
      recipe: recipe,
      isThrowing: index.throwingFakes.contains(recipe.typeName),
      resolver: &resolver
    )
    return GeneratedPreviewable(debug: [generated.debug], release: [generated.release])
  }
}
