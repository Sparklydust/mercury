//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Mercury

/// Exercises eager construction of a fresh nested double.
@PreviewableDouble
protocol ParentServiceProtocol: Sendable {
  var child: any ChildServiceProtocol { get }
}
