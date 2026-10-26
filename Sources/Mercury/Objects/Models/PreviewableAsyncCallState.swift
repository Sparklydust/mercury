//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

/// Protects a call's single suspension against resume and cancellation races.
struct PreviewableAsyncCallState {

  var resumed: Bool
  var continuation: CheckedContinuation<Void, Never>?
}
