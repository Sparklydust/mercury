//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

/// Verifies the declarations generated for an annotated protocol, structure and class.
@Suite
struct PreviewableSourceGeneratorTests {

    private let source = """
    import Foundation
    
    enum Mode {
      case ready
      case unavailable
    }
    
    @PreviewableDouble
    protocol ServiceProtocol {
      var state: Mode { get set }
      func load(id: Int) async throws -> [String]
    }
    
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

    // MARK: - Generator
    @Test(arguments: [
        "#if DEBUG\n/// A test double for `ServiceProtocol`.",
        "/// - Important: Available only in Debug builds.",
        "// Mock values",
        "// Preview value",
        "// Spy values",
        "// Protocol requirements",
        "/// The shared double used by previews.",
        "/// The protocol method names invoked on this double.",
        "private(set) var calledMethods: [String] = []",
        "private(set) var passedParameters: [String: [[Any?]]] = [:]",
        "var stateStub: Mode = Mode.ready",
        "var state: Mode {\n    get { stateStub }\n    set { stateStub = newValue }\n  }",
        "var loadErrorStub: (any Error)?",
        "var loadStub: [String] = []",
        "passedParameters[#function, default: []].append([id])",
        "/// The shared `ServiceDouble` for SwiftUI preview dependency injection.",
        "nonisolated var serviceDouble: any ServiceProtocol",
        "serviceDouble is unavailable outside Debug builds and SwiftUI previews"
    ])
    func generator_protocolIsAnnotated_expectedDoubleMemberIsGenerated(
        _ expected: String
    ) throws {
        let result = try PreviewableSourceGenerator.generate(from: [source])

        #expect(
            result.contains(expected),
            "Generated source must contain `\(expected)`."
        )
    }

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

    @Test(arguments: [
        "servicePreview",
        "func serviceDouble(",
        "func previewable()"
    ])
    func generator_protocolIsAnnotated_obsoleteAPIIsNotGenerated(
        _ forbidden: String
    ) throws {
        let result = try PreviewableSourceGenerator.generate(from: [source])

        #expect(
            !result.contains(forbidden),
            "Generated source must not contain `\(forbidden)`."
        )
    }

    @Test(arguments: [
        "var identifierStub: UUID = UUID()",
        "var identifier: UUID { identifierStub }",
        "func reset()",
        "var nameStub: String = .init()"
    ])
    func generator_protocolInheritsInModuleProtocol_requirementsAreFlattened(
        _ expected: String
    ) throws {
        let result = try PreviewableSourceGenerator.generate(from: [
            """
            @PreviewableDouble
            protocol BaseProtocol {
              var identifier: UUID { get }
              func reset()
            }

            @PreviewableDouble
            protocol ServiceProtocol: BaseProtocol, AnyObject, Sendable {
              var name: String { get }
            }
            """
        ])

        #expect(
            result.contains(expected),
            "Flattened source must contain `\(expected)`."
        )
    }

    @Test
    func generator_doubleIsGenerated_typeIsConcurrencySafe() throws {
        let result = try PreviewableSourceGenerator.generate(from: [
            "@PreviewableDouble\nprotocol ServiceProtocol { var name: String { get } }"
        ])

        let isSendable = result.contains(
            "final class ServiceDouble: ServiceProtocol, @unchecked Sendable {"
        )
        let previewIsUntrapped = result.contains("nonisolated static let preview = ServiceDouble()")
            && !result.contains("assumeIsolated")

        #expect(
            isSendable && previewIsUntrapped,
            "Doubles must compile under the Swift 6 language mode without trapping off the main thread."
        )
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

    /// Every unsupported declaration must fail the build with a message naming the fix.
    @Test(arguments: [
        (
            """
            protocol BaseProtocol { func reset() }
            @PreviewableDouble
            protocol ServiceProtocol: Codable { var name: String { get } }
            """,
            "cannot read the requirements of 'Codable'"
        ),
        (
            """
            #if DEBUG
            @PreviewableDouble
            protocol ServiceProtocol { var name: String { get } }
            #endif
            """,
            "declared inside a #if block"
        ),
        (
            """
            @PreviewableDouble
            protocol Service { var a: String { get } }
            @PreviewableDouble
            protocol ServiceProtocol { var b: String { get } }
            """,
            "both generate 'ServiceDouble'"
        ),
        (
            """
            @PreviewableFake
            struct Model { private let secret: String; let value: String }
            """,
            "private property 'secret' appears in the memberwise initializer"
        ),
        (
            """
            @PreviewableFake
            struct Model { private var secret: String = "x"; let value: String }
            """,
            "private property 'secret' appears in the memberwise initializer"
        ),
        (
            """
            @PreviewableDouble
            protocol ServiceProtocol { func load(); func load(id: Int) }
            """,
            "does not support overloaded requirement 'load'"
        ),
        (
            """
            @PreviewableDouble
            protocol ServiceProtocol { associatedtype Item; func load() -> Item }
            """,
            "does not support associated types or subscripts"
        ),
        (
            """
            @PreviewableDouble
            protocol ServiceProtocol { subscript(index: Int) -> String { get } }
            """,
            "does not support associated types or subscripts"
        ),
        (
            """
            @PreviewableDouble
            protocol ServiceProtocol<Item> { var name: String { get } }
            """,
            "does not support protocols with associated types or generic constraints"
        ),
        (
            """
            @PreviewableDouble
            protocol ServiceProtocol { static var shared: String { get } }
            """,
            "does not support static property requirements"
        ),
        (
            """
            @PreviewableDouble
            protocol ServiceProtocol { static func make() }
            """,
            "does not support static or generic method requirements"
        ),
        (
            """
            @PreviewableDouble
            protocol ServiceProtocol { func load<Item>(value: Item) }
            """,
            "does not support static or generic method requirements"
        ),
        (
            """
            @PreviewableDouble
            protocol ServiceProtocol { func log(messages: String...) }
            """,
            "does not support variadic parameters"
        ),
        (
            """
            @PreviewableDouble
            protocol ServiceProtocol { func load(_: Int) }
            """,
            "requires a named local parameter"
        ),
        (
            """
            @PreviewableFake
            final class Model { let value: String }
            """,
            "classes require mutable fake properties and an accessible init()"
        ),
        (
            """
            @PreviewableFake
            final class Model { var value: String; init(value: String) { self.value = value } }
            """,
            "the generated initializer calls 'init()'"
        ),
        (
            """
            @PreviewableFake
            final class Model { var value: String }
            """,
            "'value' has no initial value, so the class has no 'init()' to call"
        ),
        (
            """
            @PreviewableFake
            struct Model { let value: String; init(from other: Model) { self = other } }
            """,
            "declaring an initializer suppresses the memberwise one"
        )
    ])
    func generator_declarationIsUnsupported_diagnosticNamesTheFix(
        _ source: String,
        _ expected: String
    ) {
        let message = generatorDiagnosticMessage(for: source)

        #expect(
            message?.contains(expected) == true,
            "Expected a diagnostic containing `\(expected)`, got `\(message ?? "no diagnostic")`."
        )
    }

    @Test
    func generator_declarationIsUnsupported_diagnosticPointsAtTheSourceLine() throws {
        let file = PreviewableSourceFile(
            path: "Service.swift",
            text: """
            import Foundation

            @PreviewableDouble
            protocol ServiceProtocol: Codable { var name: String { get } }
            """
        )

        let diagnostic = try #require(generatorDiagnostic(for: file))

        #expect(diagnostic.path == "Service.swift")
        #expect(diagnostic.line == 3)
        #expect(diagnostic.description.hasPrefix("Service.swift:3:1: error: "))
    }

    @Test(arguments: [
        (
            """
            enum Status { case failed(Error); case idle }

            @PreviewableFake
            struct Session { var status: Status }
            """,
            "status: Status = Status.idle"
        ),
        (
            """
            enum Outer { enum Mode { case automatic } }

            @PreviewableFake
            struct Session { var mode: Outer.Mode }
            """,
            "mode: Outer.Mode = Outer.Mode.automatic"
        )
    ])
    func generator_requirementIsEnumeration_defaultNamesACaseInScope(
        _ source: String,
        _ expected: String
    ) throws {
        let result = try PreviewableSourceGenerator.generate(from: [source])

        #expect(
            result.contains(expected),
            "The default must name a parameterless case through its enclosing types, got `\(result)`."
        )
    }

    @Test
    func generator_requirementRethrows_errorIsNotReplayed() throws {
        let result = try PreviewableSourceGenerator.generate(from: [
            """
            @PreviewableDouble
            protocol MappingProtocol {
              func map(_ transform: () throws -> Int) rethrows -> Int
            }
            """
        ])

        let keepsSignature = result.contains("func map(_ transform: () throws -> Int) rethrows -> Int {")
        let hasNoErrorStub = !result.contains("mapErrorStub")

        #expect(
            keepsSignature && hasNoErrorStub,
            "A `rethrows` requirement may only throw from its closure argument, so no error stub can exist."
        )
    }

    @Test
    func generator_requirementHasTypedThrows_stubMatchesTheThrownType() throws {
        let result = try PreviewableSourceGenerator.generate(from: [
            """
            enum MappingError: Error { case broken }

            @PreviewableDouble
            protocol MappingProtocol {
              func load() throws(MappingError) -> Int
            }
            """
        ])

        #expect(
            result.contains("var loadErrorStub: (MappingError)?"),
            "A typed `throws` requirement cannot throw an `any Error`, so the stub must carry the thrown type."
        )
    }

    @Test
    func generator_requirementIsRestated_itIsGeneratedOnce() throws {
        let result = try PreviewableSourceGenerator.generate(from: [
            """
            protocol BaseProtocol { func load() -> Int }

            @PreviewableDouble
            protocol RefinedProtocol: BaseProtocol { func load() -> Int }
            """
        ])

        #expect(
            result.components(separatedBy: "func load() -> Int {").count == 2,
            "Restating an inherited requirement must generate one witness, not a duplicate or a diagnostic."
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
    func generator_methodIsCalledTwice_everyInvocationIsRecorded() throws {
        let result = try PreviewableSourceGenerator.generate(from: [
            "@PreviewableDouble\nprotocol ServiceProtocol { func load(id: Int) }"
        ])

        #expect(
            result.contains("passedParameters[#function, default: []].append([id])"),
            "Arguments must accumulate per invocation, matching the calls recorded in `calledMethods`."
        )
    }

    /// Every annotation must produce either output or a diagnostic, never silence.
    @Test(arguments: [
        """
        enum Namespace {
          @PreviewableDouble
          protocol ServiceProtocol { var name: String { get } }
        }
        """,
        """
        enum Namespace {
          @PreviewableFake
          struct Model { let value: String }
        }
        """
    ])
    func generator_declarationIsNested_outputIsGenerated(_ source: String) throws {
        let result = try PreviewableSourceGenerator.generate(from: [source])

        #expect(
            result.contains("Namespace."),
            "Nested declarations must generate qualified output rather than nothing."
        )
    }

    // MARK: - External fakes
    @Test(arguments: [
        "extension AppCheckToken {",
        "static func fake(",
        "token: String = ",
        "expirationDate: Date = Date(timeIntervalSince1970: 1704067200)",
        ") -> AppCheckToken {",
        "token: token,",
        "expirationDate: expirationDate"
    ])
    func generator_extensionDeclaresMembers_factoryMatchesTheDeclaredMembers(_ expected: String) throws {
        let result = try PreviewableSourceGenerator.generate(from: [Self.externalSource])

        #expect(
            result.contains(expected),
            "A type the generator cannot read must produce the factory its declared members describe."
        )
    }

    @Test
    func generator_extensionDeclaresMembers_noConvenienceInitializerIsGenerated() throws {
        let result = try PreviewableSourceGenerator.generate(from: [Self.externalSource])

        #expect(
            !result.contains("convenience init("),
            "An initializer added from another module could not reach the extended type's stored properties."
        )
    }

    @Test
    func generator_externalTypeIsFaked_ownedPropertyDefaultsToIt() throws {
        let result = try PreviewableSourceGenerator.generate(from: [
            """
            \(Self.externalSource)

            @PreviewableFake
            struct Credentials {
              let appCheck: AppCheckToken
            }
            """
        ])

        #expect(
            result.contains("appCheck: AppCheckToken = AppCheckToken.fake()"),
            "An annotated external type must be usable as a property type, exactly like an owned one."
        )
    }

    @Test
    func generator_extensionDeclaresNoMembers_diagnosticNamesTheMissingArgument() {
        let message = generatorDiagnosticMessage(for: """
        @PreviewableFake
        extension AppCheckToken {}
        """)

        #expect(
            message == """
            @PreviewableFake cannot read 'AppCheckToken', declared outside this module \
            — list its initializer parameters in 'members:'
            """,
            "Without members the generator has nothing to describe the type, and must say so."
        )
    }

    @Test
    func generator_memberIsNotANameTypePair_diagnosticIsEmitted() {
        let message = generatorDiagnosticMessage(for: """
        @PreviewableFake(members: [("token", "String")])
        extension AppCheckToken {}
        """)

        #expect(
            message == """
            @PreviewableFake expects every member of 'AppCheckToken' to read as \
            ('name', Type.self)
            """,
            "A member spelled as anything but a name and a metatype cannot be turned into a parameter."
        )
    }

    @Test
    func generator_memberListIsEmpty_diagnosticIsEmitted() {
        let message = generatorDiagnosticMessage(for: """
        @PreviewableFake(members: [])
        extension AppCheckToken {}
        """)

        #expect(
            message == """
            @PreviewableFake requires at least one member for 'AppCheckToken' \
            — list the values its initializer takes
            """,
            "A factory taking no values would construct nothing the caller could vary."
        )
    }

    @Test
    func generator_memberNameIsRepeated_diagnosticIsEmitted() {
        let message = generatorDiagnosticMessage(for: """
        @PreviewableFake(members: [("token", String.self), ("token", Int.self)])
        extension AppCheckToken {}
        """)

        #expect(
            message == "@PreviewableFake requires distinct member names for 'AppCheckToken'",
            "Repeating a name would generate a factory with two identical parameter labels."
        )
    }

    @Test
    func generator_ownedTypeDeclaresMembers_diagnosticIsEmitted() {
        let message = generatorDiagnosticMessage(for: """
        @PreviewableFake(members: [("value", Int.self)])
        struct Model { let value: Int }
        """)

        #expect(
            message == """
            @PreviewableFake reads the stored properties of a type declared in this module \
            — remove 'members:'
            """,
            "Declared members and read stored properties could disagree, so only one of them may be given."
        )
    }

    @Test
    func generator_typeIsFakedTwice_diagnosticIsEmitted() {
        let message = generatorDiagnosticMessage(for: """
        @PreviewableFake(members: [("token", String.self)])
        extension AppCheckToken {}

        @PreviewableFake(members: [("token", String.self)])
        extension AppCheckToken {}
        """)

        #expect(
            message == """
            'AppCheckToken' is annotated with @PreviewableFake more than once \
            — keep a single annotation
            """,
            "Two annotations on the same type would generate the same factory twice."
        )
    }

    private static let externalSource = """
    import Foundation

    @PreviewableFake(members: [("token", String.self), ("expirationDate", Date.self)])
    extension AppCheckToken {}
    """
}
