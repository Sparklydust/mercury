//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import Foundation
import SQMacrosKit

/// Namespaces the declarations below, exercising generation for nested types.
enum Trading {

    /// A nested structure, faked through its qualified name.
    @PreviewableFake
    struct Order {
        let symbol: String
        let quantity: Int
    }

    /// A nested protocol, doubled through its qualified name.
    @PreviewableDouble
    protocol OrderServiceProtocol {
        var pending: [String] { get }
        func submit(order: String) throws
    }
}
