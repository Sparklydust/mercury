//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Testing

@Suite
struct PreviewableFakeBehaviourTests {

    @Test
    func fake_noArgumentsAreGiven_defaultsAreDistinct() {
        let account = Account.fake()

        let result = account.owner.isEmpty == false
        && account.owner != account.label
        && account.openedAt != account.closedAt
        && account.identifier != UUID()

        #expect(result, "Generated fake defaults must be populated and distinct.")
    }

    @Test
    func fake_valuesAreProvided_overridesAreApplied() {
        let account = Account.fake(owner: "Roland", balance: 1_250.5)

        #expect(
            account.owner == "Roland" && account.balance == 1_250.5,
            "A developer must be able to supply the values a preview or test needs."
        )
    }

    @Test
    func fake_propertyIsOwnedType_nestedFakeIsUsed() {
        let portfolio = Portfolio.fake()

        #expect(
            portfolio.account.owner.isEmpty == false,
            "A stored property of an owned type must be filled from that type's fake."
        )
    }

    @Test
    func fake_typeIsNested_factoryIsQualified() {
        let order = Trading.Order.fake(symbol: "SQ")

        #expect(order.symbol == "SQ", "A nested type must expose its fake through its qualified name.")
    }

    @Test
    func fake_typeIsGeneric_callerSuppliesGenericValue() {
        let page = Page.fake(element: 42)

        #expect(page.element == 42, "A generic fake must accept the caller's value.")
    }

    @Test
    func fake_typeIsClass_convenienceInitializerIsAvailable() {
        let session = Session.fake(token: "token")

        #expect(session.token == "token", "A class fake must be constructible with overrides.")
    }

    @Test @MainActor
    func fake_typeIsGloballyIsolated_factoryIsUsableOnThatActor() {
        let state = ViewState.fake(title: "Markets")

        #expect(
            state.title == "Markets",
            "A globally isolated type must stay constructible from its own actor, where its initializer lives."
        )
    }

    @Test
    func fake_typeIsDeclaredOutsideTheModule_declaredParametersBecomeFactoryParameters() {
        let locale = Locale.fake(identifier: "fr_CH")

        #expect(
            locale.identifier == "fr_CH",
            "A type the generator cannot read must still be constructible through its declared parameters."
        )
    }

    @Test
    func fake_externalMemberIsOptional_defaultIsNil() {
        let item = URLQueryItem.fake(name: "symbol")

        #expect(
            item.name == "symbol" && item.value == nil,
            "A declared optional member must default to nil, exactly like an owned optional property."
        )
    }
}
