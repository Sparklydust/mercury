//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

/// Covers the double `@PreviewableDouble` generates from a protocol.
@Suite
struct PreviewableDoubleGeneratorTests {

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
    """

    @Test(arguments: [
        "/// A test double for `ServiceProtocol`.",
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
        "nonisolated var serviceDouble: ServiceDouble",
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
    func generator_methodIsCalledTwice_everyInvocationIsRecorded() throws {
        let result = try PreviewableSourceGenerator.generate(from: [
            "@PreviewableDouble\nprotocol ServiceProtocol { func load(id: Int) }"
        ])

        #expect(
            result.contains("passedParameters[#function, default: []].append([id])"),
            "Arguments must accumulate per invocation, matching the calls recorded in `calledMethods`."
        )
    }

    @Test
    func generator_requirementThrows_errorQueueIsConsumedBeforeTheStoredError() throws {
        let result = try PreviewableSourceGenerator.generate(from: [
            """
            @PreviewableDouble
            protocol MappingProtocol {
              func load() throws(MappingError) -> Int
            }

            enum MappingError: Error { case broken }
            """
        ])

        let declaresQueue = result.contains("var loadErrorsStub: [MappingError] = []")
        let consumesQueueFirst = result.contains(
            """
                if !loadErrorsStub.isEmpty { throw loadErrorsStub.removeFirst() }
                if let loadErrorStub { throw loadErrorStub }
            """
        )

        #expect(
            declaresQueue && consumesQueueFirst,
            "The queue must carry the thrown type and be consumed before the stored error."
        )
    }

    @Test
    func generator_doubleIsGenerated_onlyDebugBuildsDeclareIt() throws {
        let result = try PreviewableSourceGenerator.generate(from: [
            "@PreviewableDouble\nprotocol ServiceProtocol { var name: String { get set } }"
        ])
        let unconditionalSource = result.components(separatedBy: "#if DEBUG").first ?? String()

        let isDebugOnly = !unconditionalSource.contains("ServiceDouble")
        let accessorCompilesEverywhere = result.contains("nonisolated var serviceDouble: ServiceDouble")
            && result.contains("nonisolated var serviceDouble: any ServiceProtocol")

        #expect(
            isDebugOnly && accessorCompilesEverywhere,
            "Production code must never reach a double, while the accessor injecting it must still compile."
        )
    }

    @Test
    func generator_protocolRequiresParameterlessInitializer_noDuplicateWitnessIsGenerated() throws {
        let result = try PreviewableSourceGenerator.generate(from: [
            "@PreviewableDouble\nprotocol FeedProtocol { init() }"
        ])

        #expect(
            result.components(separatedBy: "init()").count == 2,
            "The double already declares `init()`, so witnessing the requirement again would not compile."
        )
    }
}
