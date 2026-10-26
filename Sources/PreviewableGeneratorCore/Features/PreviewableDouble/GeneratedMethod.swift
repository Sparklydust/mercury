//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import SwiftParser
import SwiftSyntax

/// The generated stubs and the protocol requirement they witness.
struct GeneratedMethod {

  /// The response and error configuration members in emission order.
  let stubs: [String]
  /// The method witness that records the invocation and applies configured responses.
  let requirement: String

  /// The callable body reused when rendering async properties and subscript accessors.
  var body: String {
    Parser
      .parse(source: requirement)
      .statements
      .first!
      .item
      .as(FunctionDeclSyntax.self)!
      .body!
      .trimmedDescription
  }
}
