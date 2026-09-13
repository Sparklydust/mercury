//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

/// Exercises scalar, date, identifier and URL defaults on a structure.
@PreviewableFake
struct Account {
  let identifier: UUID
  let owner: String
  let label: String
  let balance: Double
  let openedAt: Date
  let closedAt: Date
  let statement: URL
  let isActive: Bool
}

/// Exercises a stored property whose type is another owned, faked type.
@PreviewableFake
struct Portfolio {
  let account: Account
  let positions: [String]
  let updatedAt: Date
}

/// Exercises a private property that stays private because it carries its own value.
@PreviewableFake
struct Preferences {
  private let storageKey: String = "preferences"
  let locale: String
  let isCompact: Bool
}

/// Exercises a generic type, whose optional generic value defaults to nil.
@PreviewableFake
struct Page<Element> {
  let element: Element?
  let index: Int
}

/// Exercises a class, which receives a convenience initializer alongside its factory.
@PreviewableFake
final class Session {
  var token: String = ""
  var expiresAt: Date = .now

  init() {}
}

/// Exercises a `public` structure so the generated factory keeps the same access level.
@PreviewableFake
public struct PublicModel {
  public let title: String
  public let amount: Int
}

/// Exercises a globally isolated type, whose initializer the factory can only reach on its actor.
@PreviewableFake
@MainActor
final class ViewState {
  var title: String = ""
  var isLoading: Bool = false

  init() {}
}
