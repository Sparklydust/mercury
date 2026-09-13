//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
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
        let printedParameters: String
        if parameters.isEmpty {
            printedParameters = "()"
        } else if parameters.count == 1 {
            printedParameters = "(\(parameters[0]))"
        } else {
            printedParameters = "(\n  \(parameters.joined(separator: ",\n  "))\n)"
        }

        let printedEffects = effectSpecifiers.map { " \($0.trimmedDescription)" } ?? String()
        let printedReturnClause = returnClause.map { " \($0.trimmedDescription)" } ?? String()
        return printedParameters + printedEffects + printedReturnClause
    }
}
