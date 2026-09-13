//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Testing

struct ConcurrentDoubleBehaviourTests {

  @Test
  func double_callsAreConcurrent_everyInvocationIsRecorded() async throws {
    let double = ConcurrentServiceDouble()

    try await withThrowingTaskGroup(of: String.self) { group in
      for key in 0..<1_000 { group.addTask { try await double.load(key: key) } }
      for try await _ in group {}
    }
    let result = double.passedParameters["load(key:)"]?.compactMap { $0.first as? Int }.sorted()

    #expect(result == Array(0..<1_000))
  }

  @Test
  func double_errorsAreQueued_concurrentCallsConsumeEachErrorOnce() async {
    let double = ConcurrentServiceDouble()
    double.loadErrorsStub = Array(repeating: ConstructionError.invalid, count: 100)

    let result = await withTaskGroup(of: Int.self) { group in
      for key in 0..<200 {
        group.addTask {
          do {
            _ = try await double.load(key: key)
            return 0
          } catch { return 1 }
        }
      }
      return await group.reduce(0, +)
    }

    #expect(result == 100)
  }

  @Test
  func double_queueIsMutatedConcurrently_everyAppendIsPreserved() async {
    let double = ConcurrentServiceDouble()

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<200 { group.addTask { double.loadErrorsStub.append(ConstructionError.invalid) } }
    }
    let result = double.loadErrorsStub.count

    #expect(result == 200)
  }

  @Test
  func double_parentsAreConstructed_nestedDefaultsAreIndependent() {
    let first = ParentServiceDouble()
    let second = ParentServiceDouble()

    (first.child as? ChildServiceDouble)?.count = 42
    let result = second.child.count

    #expect(result == 0)
  }

  @Test
  func genericMethod_responsesHaveDifferentTypes_eachTypeKeepsItsResponse() async throws {
    let double = ConcurrentServiceDouble()
    double.makeStub.set("value", for: String.self)
    double.makeStub.set(42, for: Int.self)

    let result = (try await double.make(String.self), try await double.make(Int.self))

    #expect(result == ("value", 42))
  }

  @Test
  func genericMethod_optionalNilIsConfigured_nilIsReturned() async throws {
    let double = ConcurrentServiceDouble()
    double.makeStub.set(nil, for: String?.self)

    let result = try await double.make(String?.self)

    #expect(result == nil)
  }

  @Test
  func genericMethod_responseIsReplaced_newResponseIsReturned() async throws {
    let double = ConcurrentServiceDouble()
    double.makeStub.set(1, for: Int.self)
    double.makeStub.remove(for: Int.self)
    double.makeStub.set(2, for: Int.self)

    let result = try await double.make(Int.self)

    #expect(result == 2)
  }
}
