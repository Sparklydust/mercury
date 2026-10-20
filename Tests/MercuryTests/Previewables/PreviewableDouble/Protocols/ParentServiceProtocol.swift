//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

/// Exercises eager construction of a fresh nested double.
@PreviewableDouble
protocol ParentServiceProtocol: Sendable {
  var child: any ChildServiceProtocol { get }
}
