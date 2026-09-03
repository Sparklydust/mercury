//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// A build failure that points at the declaration responsible for it.
///
/// The description uses the `path:line:column: error: message` form that Xcode parses, so the failure is
/// reported inline on the offending declaration instead of as an opaque tool crash.
public struct PreviewableDiagnostic: Error, CustomStringConvertible, Equatable, Sendable {

    /// The file containing the declaration.
    public let path: String
    /// The one-based line of the declaration.
    public let line: Int
    /// The one-based column of the declaration.
    public let column: Int
    /// The explanation of what the developer must change.
    public let message: String
    /// The Xcode-parsable representation of the diagnostic.
    public var description: String {
        "\(path):\(line):\(column): error: \(message)"
    }
}
