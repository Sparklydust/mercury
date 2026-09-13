//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Testing

@Suite
struct ConcurrentDoubleBehaviourTests {

  private let sut = ConcurrentServiceDouble()

  @Test
  func double_callsAreConcurrent_everyInvocationIsRecorded() async throws {
    let expected = Array(0..<1_000)

    try await withThrowingTaskGroup(of: String.self) { group in
      for key in expected { group.addTask { try await sut.load(key: key) } }
      for try await _ in group {}
    }
    let result = sut.passedParameters["load(key:)"]?.compactMap { $0.first as? Int }.sorted()

    #expect(result == expected, "Concurrent invocations must preserve every supplied key.")
  }

  @Test
  func double_errorsAreQueued_concurrentCallsConsumeEachErrorOnce() async {
    let expected = 100
    sut.loadErrorsStub = Array(repeating: ConstructionError.invalid, count: expected)

    let result = await withTaskGroup(of: Int.self) { group in
      for key in 0..<200 {
        group.addTask {
          do {
            _ = try await sut.load(key: key)
            return 0
          } catch { return 1 }
        }
      }
      return await group.reduce(0, +)
    }

    #expect(result == expected, "Each queued error must be consumed exactly once.")
  }

  @Test
  func double_queueIsMutatedConcurrently_everyAppendIsPreserved() async {
    let expected = 200

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<expected { group.addTask { sut.loadErrorsStub.append(ConstructionError.invalid) } }
    }
    let result = sut.loadErrorsStub.count

    #expect(result == expected, "Concurrent queue mutations must retain every append.")
  }

  @Test
  func double_parentsAreConstructed_nestedDefaultsAreIndependent() throws {
    let first = ParentServiceDouble()
    let second = ParentServiceDouble()
    let childDouble = try #require(first.child as? ChildServiceDouble)
    let expected = 0

    childDouble.count = 42
    let result = second.child.count

    #expect(result == expected, "Mutating one parent must leave another parent's child unchanged.")
  }

  @Test
  func genericMethod_responsesHaveDifferentTypes_eachTypeKeepsItsResponse() async throws {
    let expected = ("value", 42)
    sut.makeStub.set(expected.0, for: String.self)
    sut.makeStub.set(expected.1, for: Int.self)

    let result = (try await sut.make(String.self), try await sut.make(Int.self))

    #expect(result == expected, "Each concrete return type must retain its own response.")
  }

  @Test
  func genericMethod_optionalNilIsConfigured_nilIsReturned() async throws {
    sut.makeStub.set(nil, for: String?.self)

    let result = try await sut.make(String?.self)

    #expect(result == nil, "An explicitly configured optional nil must be returned.")
  }

  @Test
  func genericMethod_responseIsRemovedAndReconfigured_newResponseIsReturned() async throws {
    let expected = 2
    sut.makeStub.set(1, for: Int.self)
    sut.makeStub.remove(for: Int.self)
    sut.makeStub.set(expected, for: Int.self)

    let result = try await sut.make(Int.self)

    #expect(result == expected, "Reconfiguration after removal must return the new response.")
  }
}
