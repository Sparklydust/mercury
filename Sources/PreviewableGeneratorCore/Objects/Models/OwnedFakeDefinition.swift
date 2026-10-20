//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Retains the declaration data needed to validate one locally declared fake.
struct OwnedFakeDefinition {

  let members: MemberBlockItemListSyntax
  let modifiers: DeclModifierListSyntax
  let genericClause: GenericParameterClauseSyntax?
  let isClass: Bool
}
