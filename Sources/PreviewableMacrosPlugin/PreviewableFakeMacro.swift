import SwiftSyntax
import SwiftSyntaxMacros

/// Validates structure and class declarations annotated with `PreviewableFake`.
struct PreviewableFakeMacro: ExtensionMacro {

  /// Validates that the attached declaration supports Previewable fake generation.
  /// - Throws: When the declaration is not a structure or class.
  static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard declaration.is(StructDeclSyntax.self) || declaration.is(ClassDeclSyntax.self) else {
      throw PreviewableMacroError.message(
        "@PreviewableFake can only be applied to a structure or class"
      )
    }
    _ = node
    _ = type
    _ = protocols
    _ = context
    return []
  }
}
