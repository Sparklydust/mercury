//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

/// Exercises scalars, collections, optionals, settable properties, enumerations, inheritance and markers.
@PreviewableDouble
protocol CatalogueServiceProtocol: IdentifiableServiceProtocol, AnyObject, Sendable {
  var title: String { get }
  var count: Int { get set }
  var subtitle: String? { get }
  var tags: [String] { get }
  var lookup: [String: Int] { get }
  var state: LoadingState { get }
  var updatedAt: Date { get }
  var endpoint: URL { get }
  func load(page: Int) async throws -> [String]
  func refresh()
  func observe(handler: (Int) -> Void, token: String)
}
