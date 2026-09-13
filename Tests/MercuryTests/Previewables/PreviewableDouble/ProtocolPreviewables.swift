//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

/// The loading state used to exercise enumeration defaults.
enum LoadingState {
  case idle
  case loading
}

/// A base protocol whose requirements must be flattened into every derived double.
@PreviewableDouble
protocol IdentifiableServiceProtocol: Sendable {
  var identifier: UUID { get }
  func reset()
}

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

/// Exercises closures, tuples, existentials and `Result` in requirement position.
@PreviewableDouble
protocol CompositionServiceProtocol {
  var onChange: @Sendable () -> Void { get }
  var transform: @Sendable (Int) -> String { get }
  var loader: @Sendable (String) async throws -> Data { get }
  var coordinate: (Int, Int) { get }
  var labelled: (latitude: Double, longitude: Double) { get }
  var delegate: any IdentifiableServiceProtocol { get }
  var outcome: Result<Int, any Error> { get }
  var owned: Account { get }
}

/// Exercises a global-actor isolated protocol.
@MainActor
@PreviewableDouble
protocol PresentationServiceProtocol {
  var headline: String { get }
  func present()
}

/// Exercises a `public` protocol so the generated double keeps the same access level.
@PreviewableDouble
public protocol PublicServiceProtocol {
  var name: String { get }
  func send(message: String) throws
}

/// Exercises an initializer requirement, which a double must witness to conform at all.
@PreviewableDouble
protocol FactoryProtocol {
  init(name: String)
  func reload()
}
