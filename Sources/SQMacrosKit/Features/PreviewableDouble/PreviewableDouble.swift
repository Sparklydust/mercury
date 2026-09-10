//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// Marks a protocol for Debug-only test-double generation.
///
/// The build tool generates a conforming `Double` with automatic stubs, method and parameter recording, and a shared
/// `preview` instance. It also emits a lower-camel-case double accessor that traps outside Debug builds and
/// SwiftUI previews.
///
/// Apply the macro only to protocols without associated types or generic constraints.
@attached(peer, names: suffixed(Double))
public macro PreviewableDouble() = #externalMacro(
    module: "PreviewableMacrosPlugin",
    type: "PreviewableDoubleMacro"
)
