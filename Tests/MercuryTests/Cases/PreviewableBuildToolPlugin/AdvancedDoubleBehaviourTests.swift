//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Testing

struct AdvancedDoubleBehaviourTests {

  private var sut = AssociatedStoreDouble<String>()

  @Test
  func overloads_signaturesDiffer_eachResponseIsIndependent() {
    let double = OverloadedServiceDouble()
    double.loadIdIntStub = "number"
    double.loadIdStringStub = "text"
    double.loadNameStringStub = "name"

    let result = [double.load(id: 1), double.load(id: "1"), double.load(name: "1")]

    #expect(result == ["number", "text", "name"], "Each overload must return its own configured response.")
  }

  @Test
  func overloads_signaturesDiffer_recordingsIdentifyEachSignature() {
    let double = OverloadedServiceDouble()

    _ = double.load(id: 1)
    _ = double.load(id: "1")
    let result = Set(double.calledMethods).count

    #expect(result == 2, "Overloads with identical labels must have distinct recording identities.")
  }

  @Test
  func associatedType_responseIsConfigured_originalMethodsReturnValues() {
    sut.valueStub = "first"
    sut.valueForIntStub = "second"

    let result = [sut.value(), sut.value(for: 1)]

    #expect(result == ["first", "second"], "Associated responses must preserve the concrete specialization.")
  }

  @Test
  func associatedType_optionalDefault_isNil() {
    let result = sut.current

    #expect(result == nil, "An associated optional must retain its valid nil default.")
  }

  @Test
  func associatedType_concreteBinding_usesConcreteDefault() {
    let double = ConcreteStoreDouble()

    let result = double.value()

    #expect(result == "", "A concrete same-type binding must use the existing scalar default.")
  }

  @Test
  func associatedTypes_transitiveConcreteBindings_resolveWithoutGenericParameters() {
    let double = ConcreteChainDouble()

    let result = double.value()

    #expect(result == "", "Transitive equalities must resolve every associated name to the concrete type.")
  }

  @Test
  func associatedType_optionalSpecialization_acceptsExplicitNil() {
    let double = AssociatedStoreDouble<String?>()
    double.valueStub = nil

    let result = double.value()

    #expect(result == nil, "An explicitly configured nil must differ from an unconfigured associated response.")
  }

  @Test
  func associatedTypes_dependentConstraint_preservesCollectionElement() {
    let double = CollectionStoreDouble<String, [String]>()
    double.valuesStub = ["ready"]
    double.firstStub = "ready"

    let result = double.values().first == double.first()

    #expect(result, "Dependent associated types must preserve their same-type constraint.")
  }

  @Test
  func genericPreview_accessedTwice_returnsFreshInstances() {
    let first = AssociatedStoreDouble<String>.preview

    let result = first === AssociatedStoreDouble<String>.preview

    #expect(!result, "Specialized previews must not share mutable state.")
  }

  @Test
  func subscript_indicesDiffer_returnsConstantResponse() {
    sut.subscriptStub = "configured"

    let result = [sut[1], sut[2]]

    #expect(result == ["configured", "configured"], "V1 subscripts use a constant response for every index.")
  }

  @Test
  func subscript_valueIsAssigned_preservesConfiguredResponse() {
    sut.subscriptStub = "configured"

    sut[1] = "written"
    let result = sut[1]

    #expect(result == "configured", "A subscript write must not replace its configured getter response.")
  }

  @Test
  func subscript_valueIsAssigned_recordsIndexAndValue() {
    sut[42] = "written"

    let record = sut.passedParameters.values.first?.first
    let result = record?.first as? Int == 42 && record?.last as? String == "written"

    #expect(result, "Setter recordings must retain the index and assigned value.")
  }

  @Test
  func subscript_indexIsNotHashable_remainsSupported() {
    let double = IndexedServiceDouble()
    double.subscriptNonHashableIndexStub = "ready"

    let result = double[NonHashableIndex(value: 1)]

    #expect(result == "ready", "Subscript generation must not require Hashable indices.")
  }

  @Test
  func subscript_getterIsAsync_preservesItsEffects() async throws {
    let double = AsyncIndexedServiceDouble()
    double.subscriptStub = "ready"

    let result = try await double[1]

    #expect(result == "ready", "An asynchronous throwing getter must preserve its configured response.")
  }

  @Test
  func subscript_getterIsGeneric_usesConcreteResponse() {
    let double = GenericIndexedServiceDouble()
    double.subscriptStub.set("ready", for: String.self)

    let result = double[String.self]

    #expect(result == "ready", "Generic subscripts must retrieve the configured concrete response.")
  }

  @Test
  func staticScopes_runConcurrently_remainIndependent() async throws {
    let result = try await withThrowingTaskGroup(of: Bool.self, returning: Bool.self) { group in
      for number in 0..<100 {
        group.addTask {
          try await AssociatedStoreDouble<String>.withStaticStubs {
            AssociatedStoreDouble<String>.fetchIntStub = String(number)
            await Task.yield()
            return try await AssociatedStoreDouble<String>.fetch(number) == String(number)
          }
        }
      }
      for try await passed in group where !passed { return false }
      return true
    }

    #expect(result, "Parallel scopes must never share configuration for the same double type.")
  }

  @Test
  func staticScope_childrenShareState_recordsEveryInvocation() async throws {
    let result = try await AssociatedStoreDouble<String>.withStaticStubs {
      AssociatedStoreDouble<String>.fetchIntStub = "ready"
      try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0..<300 {
          group.addTask { _ = try await AssociatedStoreDouble<String>.fetch(index) }
        }
        try await group.waitForAll()
      }
      return AssociatedStoreDouble<String>.calledMethods.count
    }

    #expect(result == 300, "Inherited task-local bindings must share synchronized reference-backed recordings.")
  }

  @Test
  func staticScope_configurationIsConcurrent_retainsCompleteAssignments() async {
    let result = await AssociatedStoreDouble<String>.withStaticStubs {
      await withTaskGroup(of: Void.self) { group in
        for index in 0..<100 { group.addTask { AssociatedStoreDouble<String>.revision = index } }
      }
      return AssociatedStoreDouble<String>.revision
    }

    #expect((0..<100).contains(result), "Concurrent assignments must be memory-safe without promising writer order.")
  }

  @Test
  func staticErrors_callsAreSequential_consumesQueueBeforePersistentError() async {
    let result = await AssociatedStoreDouble<String>.withStaticStubs {
      AssociatedStoreDouble<String>.fetchIntErrorsStub = [ScopedFailure.numbered(1), ScopedFailure.numbered(2)]
      AssociatedStoreDouble<String>.fetchIntErrorStub = ScopedFailure.numbered(3)
      var errors: [ScopedFailure] = []
      for index in 0..<3 {
        do { _ = try await AssociatedStoreDouble<String>.fetch(index) } catch let error as ScopedFailure {
          errors.append(error)
        } catch {}
      }
      return errors
    }

    #expect(
      result == [.numbered(1), .numbered(2), .numbered(3)], "Sequential calls must consume errors in FIFO order.")
  }

  @Test
  func staticErrors_childrenAppendConcurrently_preservesEveryEntry() async {
    let result = await AssociatedStoreDouble<String>.withStaticStubs {
      await withTaskGroup(of: Void.self) { group in
        for index in 0..<300 {
          group.addTask { AssociatedStoreDouble<String>.fetchIntErrorsStub.append(ScopedFailure.numbered(index)) }
        }
      }
      return AssociatedStoreDouble<String>.fetchIntErrorsStub.count
    }

    #expect(result == 300, "Concurrent queue mutations through static proxies must preserve every append.")
  }

  @Test
  func staticErrors_callsAreConcurrent_consumesEveryEntryExactlyOnce() async {
    let result = await AssociatedStoreDouble<String>.withStaticStubs {
      AssociatedStoreDouble<String>.fetchIntErrorsStub = (0..<300).map(ScopedFailure.numbered)
      return await withTaskGroup(of: Int.self, returning: Set<Int>.self) { group in
        for index in 0..<300 {
          group.addTask {
            do { _ = try await AssociatedStoreDouble<String>.fetch(index) } catch ScopedFailure.numbered(let value) {
              return value
            } catch {}
            return -1
          }
        }
        var consumed: Set<Int> = []
        for await value in group { consumed.insert(value) }
        return consumed
      }
    }

    #expect(result == Set(0..<300), "Concurrent callers must consume each queued entry once, regardless of scheduling.")
  }

  @Test
  func staticScope_nestedScopeIsCancelled_restoresOuterState() async {
    let result = await Task {
      await AssociatedStoreDouble<String>.withStaticStubs {
        AssociatedStoreDouble<String>.revision = 42
        do {
          try await AssociatedStoreDouble<String>.withStaticStubs {
            AssociatedStoreDouble<String>.revision = 99
            withUnsafeCurrentTask { $0?.cancel() }
            await Task.yield()
            try Task.checkCancellation()
          }
        } catch {}
        return AssociatedStoreDouble<String>.revision
      }
    }.value

    #expect(result == 42, "Cancellation must restore the enclosing task-local binding.")
  }

  @Test
  func staticScope_nestedScopeThrows_restoresOuterState() {
    let result = AssociatedStoreDouble<String>.withStaticStubs {
      AssociatedStoreDouble<String>.revision = 42
      do {
        try AssociatedStoreDouble<String>.withStaticStubs {
          AssociatedStoreDouble<String>.revision = 99
          throw ScopedFailure.numbered(1)
        }
      } catch {}
      return AssociatedStoreDouble<String>.revision
    }

    #expect(result == 42, "A throwing nested scope must restore the outer binding.")
  }

  @Test
  func staticScope_specializationsDiffer_keepIndependentBindings() {
    let result = AssociatedStoreDouble<String>.withStaticStubs {
      AssociatedStoreDouble<String>.revision = 42
      return AssociatedStoreDouble<Int>.withStaticStubs {
        AssociatedStoreDouble<Int>.revision = 99
        return AssociatedStoreDouble<String>.revision
      }
    }

    #expect(result == 42, "Static scopes must be keyed by the concrete generic specialization.")
  }

  @Test
  func staticSubscript_valueIsAssigned_preservesGetterResponse() {
    let result = AssociatedStoreDouble<String>.withStaticStubs {
      AssociatedStoreDouble<String>.subscriptStub = "ready"
      AssociatedStoreDouble<String>[1] = "write"
      return AssociatedStoreDouble<String>[2]
    }

    #expect(result == "ready", "Static subscript setters must record writes without changing configured responses.")
  }

  @Test
  @MainActor
  func staticScope_actorRequirement_retainsActorIsolatedArguments() {
    let payload = ScopedPayload()

    let result = ActorStaticServiceDouble.withStaticStubs {
      _ = ActorStaticServiceDouble.store(payload)
      return ActorStaticServiceDouble.passedParameters["store(_:)"]?.first?.first as? ScopedPayload
    }

    #expect(result === payload, "Actor-isolated static recordings must retain their original payload.")
  }
}
