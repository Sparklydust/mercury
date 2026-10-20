//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Testing

struct PreviewableFakeBehaviourTests {

  @Test
  func fake_stringHasNoOverride_defaultIsPopulated() {
    let result = Account.fake().owner

    #expect(!result.isEmpty, "The owner default must be populated.")
  }

  @Test
  func fake_stringsHaveNoOverrides_defaultsAreDistinct() {
    let sut = Account.fake()
    let result = sut.owner != sut.label

    #expect(result, "Separate string fields must receive distinct defaults.")
  }

  @Test
  func fake_datesHaveNoOverrides_defaultsAreDistinct() {
    let sut = Account.fake()
    let result = sut.openedAt != sut.closedAt

    #expect(result, "Separate date fields must receive distinct defaults.")
  }

  @Test
  func fake_identifierHasNoOverride_defaultIsNonzero() {
    let result = Account.fake().identifier

    #expect(
      result != UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
      "The identifier default must differ from the zero UUID."
    )
  }

  @Test
  func fake_propertyIsOwnedType_nestedFakeIsUsed() {
    let result = Portfolio.fake().account.owner

    #expect(!result.isEmpty, "A nested owned type must receive a populated fake.")
  }

  @Test
  func fake_externalMemberIsOptional_defaultIsNil() {
    let expected: String? = nil

    let result = URLQueryItem.fake(name: "symbol").value

    #expect(result == expected, "An external optional parameter must default to nil.")
  }

  @Test
  func fake_ownerIsProvided_overrideIsApplied() {
    let expected = "Roland"

    let result = Account.fake(owner: expected).owner

    #expect(result == expected, "The factory must apply the owner override.")
  }

  @Test
  func fake_balanceIsProvided_overrideIsApplied() {
    let expected = 1_250.5

    let result = Account.fake(balance: expected).balance

    #expect(result == expected, "The factory must apply the balance override.")
  }

  @Test
  func fake_typeIsNested_factoryIsQualified() {
    let expected = "SQ"

    let result = Trading.Order.fake(symbol: expected).symbol

    #expect(result == expected, "The nested factory must accept the supplied symbol.")
  }

  @Test
  func fake_typeIsGeneric_callerSuppliesGenericValue() {
    let expected = 42

    let result = Page.fake(element: expected).element

    #expect(result == expected, "The generic factory must accept the supplied value.")
  }

  @Test
  func fake_typeIsClass_convenienceInitializerAppliesOverride() {
    let expected = "token"

    let result = Session.fake(token: expected).token

    #expect(result == expected, "The class factory must apply the token override.")
  }

  @MainActor
  @Test
  func fake_typeIsGloballyIsolated_factoryIsUsableOnThatActor() {
    let expected = "Markets"

    let result = ViewState.fake(title: expected).title

    #expect(result == expected, "The isolated factory must apply its override.")
  }

  @Test
  func fake_typeIsExternal_declaredParameterIsApplied() {
    let expected = "fr_CH"

    let result = Locale.fake(identifier: expected).identifier

    #expect(result == expected, "The external factory must pass the identifier to its initializer.")
  }

  @Test
  func fake_externalRequiredMemberIsProvided_overrideIsApplied() {
    let expected = "symbol"

    let result = URLQueryItem.fake(name: expected).name

    #expect(result == expected, "The external factory must apply its required argument.")
  }
}
