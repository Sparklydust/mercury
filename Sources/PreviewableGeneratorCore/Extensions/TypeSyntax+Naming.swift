//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftParser
import SwiftSyntax

extension TypeSyntax {

  /// Parses a printed type back into syntax, or `nil` when the text does not spell a type.
  ///
  /// `String.self` reaches the generator as an expression while the default resolver matches on types:
  /// re-parsing the base inside a throwaway declaration is what bridges the two.
  static func parsed(from text: String) -> TypeSyntax? {
    let tree = Parser.parse(source: "var member: \(text)")
    guard !tree.hasError,
          let variable = tree.statements.first?.item.as(VariableDeclSyntax.self),
          let type = variable.bindings.first?.typeAnnotation?.type
            else { return .none }
    return type
  }

  /// Whether the type is a function type, looking through any attributes.
  ///
  /// A non-escaping closure cannot be stored, so a function-typed argument is never recorded.
  var isFunctionType: Bool {
    if let attributed = self.as(AttributedTypeSyntax.self) {
      return attributed.baseType.isFunctionType
    }
    return self.is(FunctionTypeSyntax.self)
  }

  /// Whether the type is optional in either spelling, and so already carries `nil` as a default.
  var isOptional: Bool {
    self.is(OptionalTypeSyntax.self) || self.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
  }

  /// Every type name written in the type, including the arguments of a generic one.
  ///
  /// Named `written` because it reports the spelling, not resolved types: a nested or aliased name reads as the
  /// tokens the developer typed.
  var writtenTypeNames: [String] {
    tokens(viewMode: .sourceAccurate).compactMap {
      guard case .identifier(let text) = $0.tokenKind else { return .none }
      return text
    }
  }

  /// Whether the type refers to the conforming type rather than a named one.
  ///
  /// A generated double is a concrete class, so `Self` in a requirement has no stored form: it would need a value
  /// of the double's own type before the double exists.
  var usesSelfType: Bool {
    tokens(viewMode: .sourceAccurate).contains {
      $0.tokenKind == .keyword(.Self) || $0.tokenKind == .identifier("Self")
    }
  }
}
