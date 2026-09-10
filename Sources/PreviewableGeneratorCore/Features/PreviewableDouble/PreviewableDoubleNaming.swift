//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// Naming rules for the types `@PreviewableDouble` generates, shared by the generator and its diagnostics.
enum PreviewableDoubleNaming {

    /// Returns the generated double name for a protocol, dropping a trailing `Protocol`.
    static func doubleName(for protocolName: String) -> String {
        let base = protocolName.hasSuffix("Protocol")
        ? String(protocolName.dropLast("Protocol".count))
        : protocolName
        return base + "Double"
    }
}
