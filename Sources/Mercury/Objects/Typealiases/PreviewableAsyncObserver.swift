//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

/// Observes an async invocation on the closure's actor before its captured response is delivered.
/// Observers cannot throw; configure failures through the generated error stubs.
public typealias PreviewableAsyncObserver = @isolated(any) @Sendable () async -> Void
