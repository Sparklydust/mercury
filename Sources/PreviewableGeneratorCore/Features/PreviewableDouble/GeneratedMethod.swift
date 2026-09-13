//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// The generated stubs and the protocol requirement they witness.
struct GeneratedMethod {

  /// The response and error configuration members in emission order.
  let stubs: [String]
  /// The method witness that records the invocation and applies configured responses.
  let requirement: String
}
