//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Generates the test double `@PreviewableDouble` derives from a protocol.
enum PreviewableDoubleGenerator: PreviewableFeatureProtocol {

  static let annotation: PreviewableAnnotation = .double

  static func conflict(in annotations: [AnnotatedDeclaration]) -> GenerationFailure? {
    var owners: [String: String] = [:]

    for annotation in annotations where annotation.annotation == .double {
      let doubleName = PreviewableDoubleNaming.doubleName(for: annotation.name)

      if let existing = owners[doubleName] {
        return GenerationFailure(
          annotation: annotation,
          message: """
            '\(annotation.name)' and '\(existing)' both generate '\(doubleName)' \
            — rename one of the protocols
            """
        )
      }
      owners[doubleName] = annotation.name
    }

    return .none
  }

  static func generate(
    from annotation: AnnotatedDeclaration,
    index: ModuleIndex,
    resolver: inout DefaultValueResolver
  ) throws -> GeneratedPreviewable {
    guard let declaration = annotation.declaration.as(ProtocolDeclSyntax.self) else {
      throw GenerationError.message("@PreviewableDouble can only be applied to a protocol")
    }
    let generated = try PreviewableDoubleRenderer.generate(
      from: declaration,
      qualifiedName: annotation.qualifiedName,
      index: index,
      resolver: &resolver
    )
    return GeneratedPreviewable(
      debug: [generated.declaration],
      unconditional: [generated.previewConfiguration],
      globalNames: generated.globalNames
    )
  }
}
