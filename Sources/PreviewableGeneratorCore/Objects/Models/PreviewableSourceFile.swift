//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// A Swift source file handed to the Previewable generator.
public struct PreviewableSourceFile: Sendable, Equatable {

    /// The path reported in diagnostics.
    public let path: String
    /// The complete Swift source text.
    public let text: String

    /// Creates a source file for generation.
    /// - Parameters:
    ///   - path: The path reported in diagnostics.
    ///   - text: The complete Swift source text.
    public init(
        path: String,
        text: String
    ) {
        self.path = path
        self.text = text
    }
}
