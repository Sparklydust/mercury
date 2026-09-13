//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// Marks a protocol for Debug-only test-double generation.
///
/// The build tool generates a conforming `Double` with automatic stubs, method and parameter recording, and a shared
/// `preview` instance. It also emits a lower-camel-case double accessor that traps outside Debug builds.
///
/// Each test requires a fresh instance to avoid sharing mutable configuration and call history.
/// Nonisolated doubles require `Sendable` stored and recorded values. Function arguments are not recorded.
/// Queued errors are consumed before the persistent error stub is checked.
/// Generic method responses use `PreviewableResponses` and trap when the concrete return type is unconfigured.
/// Protocols with associated types or protocol-level generic constraints are unsupported.
@attached(peer, names: suffixed(Double))
public macro PreviewableDouble() =
  #externalMacro(
    module: "PreviewableMacrosPlugin",
    type: "PreviewableDoubleMacro"
  )
