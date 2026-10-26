//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

/// Provides observable state before and after an awaited dependency call.
@MainActor
final class AsyncLoadingModel {

  private let service: any AsyncObservationProtocol
  private(set) var isLoading = false
  private(set) var value: String?

  init(service: any AsyncObservationProtocol) {
    self.service = service
  }

  func load() async {
    isLoading = true
    defer { isLoading = false }
    value = try? await service.load()
  }
}
