//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

/// Retains whichever outcome wins a wait's arrival, timeout, or cancellation race.
struct PreviewableAsyncWaiterState {

  var result: Result<PreviewableAsyncCall, any Error>?
  var continuation: CheckedContinuation<PreviewableAsyncCall, any Error>?
}
