//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Collects everything a generated double must witness, including the requirements it inherits.
enum PreviewableRequirementFlattener {

    /// Collects the protocol's own requirements followed by those of every base protocol declared in the module.
    static func requirements(
        of declaration: ProtocolDeclSyntax,
        index: ModuleIndex,
        visited: inout Set<String>
    ) throws -> [MemberBlockItemSyntax] {
        guard visited.insert(declaration.name.text).inserted else { return [] }
        var members = Array(declaration.memberBlock.members)

        for inherited in declaration.inheritanceClause?.inheritedTypes ?? [] {
            let name = inherited.type.trimmedDescription
            if markerProtocols.contains(name) { continue }
            guard let base = index.protocols[name] ?? index.protocols[name.simpleName] else {
                throw GenerationError.message(
                    """
                    @PreviewableDouble cannot read the requirements of '\(name)' \
                    — it is not declared in this module
                    """
                )
            }
            members.append(
                contentsOf: try requirements(of: base, index: index, visited: &visited)
            )
        }
        return members
    }

    /// Protocols that add no requirement of their own, so a double need not read them.
    private static let markerProtocols: Set<String> = [
        "AnyObject", "Sendable", "AnyActor", "Actor", "Any"
    ]
}
