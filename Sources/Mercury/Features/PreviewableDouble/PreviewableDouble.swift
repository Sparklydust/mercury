//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// Marks a protocol for Debug-only test-double generation.
///
/// The build tool generates a conforming `Double` with configurable responses and invocation recording.
/// Overloads have separate stubs. Associated types become generic parameters with explicit type aliases.
///
/// Each test requires a fresh instance to avoid sharing mutable configuration and call history.
/// Nonisolated doubles require `Sendable` stored and recorded values. Function arguments are not recorded.
/// Queued errors are consumed before the persistent error stub is checked.
/// Concurrent configuration is memory-safe but unordered; configure before spawning child tasks for deterministic use.
/// Error queues are consumed atomically in FIFO order; which concurrent caller receives an error depends on scheduling.
/// Generic method responses use `PreviewableResponses` and trap when the concrete return type is unconfigured.
/// Associated responses without defaults also require configuration. Explicit optional `nil` is a configured response.
/// Static requirements need `withStaticStubs`; inheriting child tasks share synchronized state within that scope.
/// Subscripts return a constant response and record reads and writes separately. Writes leave the response unchanged.
/// Nongeneric doubles have shared previews and global accessors. Generic doubles provide fresh `.preview` instances.
@attached(peer, names: suffixed(Double))
public macro PreviewableDouble() =
  #externalMacro(
    module: "PreviewableMacrosPlugin",
    type: "PreviewableDoubleMacro"
  )
