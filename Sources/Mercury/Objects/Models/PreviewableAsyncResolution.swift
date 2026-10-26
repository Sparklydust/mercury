//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

/// Resumes a claimed waiter after both the spy and waiter mutexes have been released.
struct PreviewableAsyncResolution: Sendable {

  let result: Result<PreviewableAsyncCall, any Error>
  let continuation: CheckedContinuation<PreviewableAsyncCall, any Error>?

  func resume() {
    continuation?.resume(with: result)
  }
}
