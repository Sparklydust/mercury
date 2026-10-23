//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// Preserves a dependent element constraint across two associated types.
@PreviewableDouble
protocol CollectionStoreProtocol<Item, Items>: Sendable where Items.Element == Item {
  associatedtype Item: Sendable
  associatedtype Items: Collection & Sendable
  func values() -> Items
  func first() -> Item
}
