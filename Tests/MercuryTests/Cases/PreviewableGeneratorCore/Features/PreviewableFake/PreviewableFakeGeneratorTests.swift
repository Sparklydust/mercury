//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

@Suite
struct PreviewableFakeGeneratorTests {

    private let source = """
    import Foundation

    @PreviewableFake
    struct Model {
      let value: String
    }

    @PreviewableFake
    final class ReferenceModel {
      var value = String()

      init() {}
    }
    """

    @Test(arguments: [
        ") -> Model {\n    .init(",
        "convenience init(\n    value: String",
        ") -> ReferenceModel {\n    .init("
    ])
    func generator_fakeIsAnnotated_expectedFactoryMemberIsGenerated(
        _ expected: String
    ) throws {
        let result = try PreviewableSourceGenerator.generate(from: [source])

        #expect(
            result.contains(expected),
            "Generated source must contain `\(expected)`."
        )
    }

    @Test
    func generator_fakeIsBuiltOutsideDebug_factoryTerminatesWithoutValues() throws {
        let generated = try PreviewableSourceGenerator.generate(from: [source])

        let releaseSource = generated
            .components(separatedBy: "#else\n")
            .dropFirst()
            .first?
            .components(separatedBy: "#endif")
            .first
        let result = releaseSource?.contains("extension Model") == true
        && releaseSource?.contains("value: String = { () -> String in preconditionFailure(") == true
        && releaseSource?.contains("preconditionFailure(\"Model.fake(...) is unavailable") == true
        && releaseSource?.contains(".init(") == false

        #expect(result, "Release fake factories must terminate without constructing preview values.")
    }

    @Test
    func generator_typeIsGeneric_callerSuppliesGenericValue() throws {
        let result = try PreviewableSourceGenerator.generate(from: [
            "@PreviewableFake\nstruct Page<Element> { let element: Element; let index: Int }"
        ])

        let requiresElement = result.contains("element: Element,")
            && !result.contains("element: Element =")
        let returnsSpecialised = result.contains(") -> Page<Element> {")

        #expect(
            requiresElement && returnsSpecialised,
            "Generic fakes must require the generic value and return the specialised type."
        )
    }

    @Test
    func generator_propertyIsPrivateWithValue_itStaysPrivate() throws {
        let result = try PreviewableSourceGenerator.generate(from: [
            """
            @PreviewableFake
            struct Preferences {
              private let storageKey: String = "preferences"
              let locale: String
            }
            """
        ])

        #expect(
            !result.contains("storageKey"),
            "A private property must never appear in the generated fake factory."
        )
    }

    @Test
    func generator_typeIsOpen_generatedMembersArePublic() throws {
        let result = try PreviewableSourceGenerator.generate(from: [
            """
            @PreviewableFake
            open class Portfolio {
              open var title: String = ""

              public init() {}
            }
            """
        ])

        #expect(
            !result.contains("open ") && result.contains("public static func fake("),
            "`open` applies to neither a static factory nor an extension member, so it must widen to `public`."
        )
    }

    @Test
    func generator_publicTypeHoldsLessVisibleType_diagnosticNamesBoth() {
        let message = generatorDiagnosticMessage(for: """
        @PreviewableFake
        struct Helper { let identifier: Int }

        @PreviewableFake
        public struct Wrapper { let helper: Helper }
        """)

        #expect(
            message == """
            @PreviewableFake cannot generate a public factory for 'Wrapper': its 'helper' parameter \
            uses the internal type 'Helper' — raise 'Helper' to public
            """,
            "A public factory cannot take an internal parameter, so the mismatch must be reported here."
        )
    }

    @Test
    func generator_publicTypeHoldsPublicType_factoryIsGenerated() throws {
        let result = try PreviewableSourceGenerator.generate(from: [
            """
            @PreviewableFake
            public struct Helper { public let identifier: Int }

            @PreviewableFake
            public struct Wrapper { public let helper: Helper }
            """
        ])

        #expect(
            result.contains("public static func fake(\n    helper: Helper = Helper.fake()"),
            "Matching visibility must stay allowed, or the check would forbid the normal case."
        )
    }

    @Test(arguments: [
        "onDone: @escaping () -> Void",
        "convenience init(\n    onDone: @escaping () -> Void"
    ])
    func generator_propertyIsAClosure_factoryParameterEscapes(_ expected: String) throws {
        let result = try PreviewableSourceGenerator.generate(from: ["""
            @PreviewableFake
            final class HandlerModel {
              var onDone: () -> Void = {}
              var onFail: ((Error) -> Void)?

              init() {}
            }
            """])

        #expect(
            result.contains(expected),
            "A non-escaping parameter cannot be stored by the initializer the factory calls."
        )
    }

    @Test
    func generator_propertyIsAnOptionalClosure_factoryParameterDoesNotEscape() throws {
        let result = try PreviewableSourceGenerator.generate(from: ["""
            @PreviewableFake
            struct MaybeModel {
              let onDone: (() -> Void)?
            }
            """])

        #expect(
            !result.contains("@escaping"),
            "`@escaping` applies to function types only, so an optional closure must be left bare."
        )
    }
}
