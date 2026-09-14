//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Testing

struct ThrowingFakeBehaviourTests {

  @Test
  func fake_initializerThrows_validDefaultIsConstructed() throws {
    let result = try CheckedValue.fake()

    #expect(result.count > 0, "The throwing initializer must accept its generated positive default.")
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

    #expect(result.value.count > 0, "The nested throwing default must be constructed successfully.")
  }

  @Test
  func fake_nestedValueIsOverridden_overrideIsUsed() throws {
    let expected = 42
    let value = try CheckedValue(count: expected)

    let result = try ThrowingContainer.fake(value: value)

    #expect(result.value.count == expected, "The supplied nested value must replace the generated default.")
  }

  @Test
  func fake_propertyHasObservers_storedValueIsProvided() {
    let expected = 42

    let result = ObservedValue.fake(count: expected)

    #expect(result.count == expected, "A property with observers must receive the supplied value.")
  }

  @Test
  func fake_nestedTypesShareNames_lexicalTypesArePreserved() {
    let expected = (FirstNamespace.Kind.first, SecondNamespace.Kind.second)

    let result = (FirstNamespace.Model.fake().kind, SecondNamespace.Model.fake().kind)

    #expect(result == expected, "Each nested factory must resolve its own lexical enumeration.")
  }
}
