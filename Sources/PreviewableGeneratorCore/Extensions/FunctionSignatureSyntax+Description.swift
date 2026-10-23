//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

extension FunctionSignatureSyntax {

  /// The signature as it must appear in generated source, wrapping a parameter list of two or more.
  var generatedDescription: String {
    let parameters = parameterClause.parameters.map { parameter in
      var parameter = parameter
      parameter.trailingComma = .none
      return parameter.trimmedDescription
    }

    let printedParameters = switch parameters.count {
    case 0: "()"
    case 1: "(\(parameters[0]))"
    default: "(\n  \(parameters.joined(separator: ",\n  "))\n)"
    }

    let printedEffects = effectSpecifiers.map { " \($0.trimmedDescription)" } ?? String()
    let printedReturnClause = returnClause.map { " \($0.trimmedDescription)" } ?? String()

    return printedParameters + printedEffects + printedReturnClause
  }
}
