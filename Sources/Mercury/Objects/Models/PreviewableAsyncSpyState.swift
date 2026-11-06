//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

/// Stores method-local observation, call delivery, and pauses behind the spy's mutex.
struct PreviewableAsyncSpyState {

  var paused = false
  var observer: PreviewableAsyncObserver?
  var calls: [PreviewableAsyncCall] = []
  var activeCalls: [PreviewableAsyncCall] = []
  var waiters: [PreviewableAsyncWaiter] = []
}
