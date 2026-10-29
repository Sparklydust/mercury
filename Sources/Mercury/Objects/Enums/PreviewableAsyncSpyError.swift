//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

/// A failure while waiting for an async invocation.
public enum PreviewableAsyncSpyError: Error, Equatable {

  /// No invocation arrived before the wait's deadline.
  case timedOut
}
