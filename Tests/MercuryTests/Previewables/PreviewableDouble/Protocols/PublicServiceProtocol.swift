//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Mercury

/// Exercises a `public` protocol so the generated double keeps the same access level.
@PreviewableDouble
public protocol PublicServiceProtocol {
  var name: String { get }
  func send(message: String) throws
}
