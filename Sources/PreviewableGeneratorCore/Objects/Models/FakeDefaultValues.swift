//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// Tracks the values already handed out so generated defaults stay distinct and easy to identify.
struct FakeDefaultValues {

  var strings: Set<String> = []
  var numbers: Set<Int> = []
  var urls: Set<Int> = []
  var uuids: Set<Int> = []
  var dates: Set<Int> = []
}
