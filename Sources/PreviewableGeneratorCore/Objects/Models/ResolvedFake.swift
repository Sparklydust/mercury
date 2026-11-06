//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

/// A validated construction recipe shared by dependency analysis and source rendering.
struct ResolvedFake {

  /// The annotation used to attribute construction failures.
  let annotation: AnnotatedDeclaration
  /// The qualified type name used for the generated extension.
  let typeName: String
  /// The factory result type, including any generic arguments.
  let returnType: String
  /// The access modifier prefix for generated members.
  let access: String
  /// The factory inputs in initializer argument order.
  let properties: [StoredProperty]
  /// Generic names that cannot receive concrete automatic defaults.
  let genericParameters: Set<String>
  /// Whether a class initializer must assign the factory properties after `init()`.
  let convenienceInitializer: Bool
  /// Whether the selected initializer declares a throwing effect.
  let initializerThrows: Bool
}
