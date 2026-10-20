//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

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
