//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// Marks a protocol for Debug-only test-double generation.
///
/// The build tool generates a conforming `Double` with automatic stubs, method and parameter recording, and a shared
/// `preview` instance. It also emits a lower-camel-case double accessor that traps outside Debug builds.
///
/// Create a fresh double for each test. Nonisolated doubles require `Sendable` stored and recorded values.
/// Generic method responses are configured by concrete return type with `PreviewableResponses`.
/// Apply the macro only to protocols without associated types or protocol-level generic constraints.
@attached(peer, names: suffixed(Double))
public macro PreviewableDouble() =
  #externalMacro(
    module: "PreviewableMacrosPlugin",
    type: "PreviewableDoubleMacro"
  )
