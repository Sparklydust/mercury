import SwiftSyntax

/// A validated construction recipe shared by dependency analysis and source rendering.
struct ResolvedFake {
  let annotation: AnnotatedDeclaration
  let typeName: String
  let returnType: String
  let access: String
  let properties: [StoredProperty]
  let genericParameters: Set<String>
  let convenienceInitializer: Bool
  let initializerThrows: Bool
}
