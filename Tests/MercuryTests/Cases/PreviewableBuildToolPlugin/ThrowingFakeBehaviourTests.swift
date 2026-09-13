import Testing

struct ThrowingFakeBehaviourTests {
  @Test
  func fake_initializerThrows_validDefaultIsConstructed() throws {
    let result = try CheckedValue.fake()

    #expect(result.count > 0)
  }

  @Test
  func fake_overrideIsInvalid_initializerErrorPropagates() {
    #expect(throws: ConstructionError.invalid) { try CheckedValue.fake(count: -1) }
  }

  @Test
  func fake_nestedConstructionThrows_errorPropagates() {
    #expect(throws: ConstructionError.invalid) {
      try ThrowingContainer.fake(value: CheckedValue.fake(count: -1))
    }
  }

  @Test
  func fake_nestedDefaultIsThrowing_defaultIsConstructed() throws {
    let result = try ThrowingContainer.fake()

    #expect(result.value.count > 0)
  }

  @Test
  func fake_nestedValueIsOverridden_overrideIsUsed() throws {
    let value = try CheckedValue(count: 42)

    let result = try ThrowingContainer.fake(value: value)

    #expect(result.value.count == 42)
  }

  @Test
  func fake_propertyHasObservers_storedValueIsProvided() {
    let result = ObservedValue.fake(count: 42)

    #expect(result.count == 42)
  }

  @Test
  func fake_nestedTypesShareNames_lexicalTypesArePreserved() {
    let result = (FirstNamespace.Model.fake().kind, SecondNamespace.Model.fake().kind)

    #expect(result == (.first, .second))
  }
}
