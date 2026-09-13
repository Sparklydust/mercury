//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

@Suite
struct DefaultValueResolverTests {

    private let compositionSource = """
    @PreviewableFake
    struct User {
      let identifier: Int
    }

    @PreviewableDouble
    protocol OtherProtocol {
      var flag: Bool { get }
    }

    @PreviewableDouble
    protocol ServiceProtocol {
      var onChange: () -> Void { get }
      var transform: (Int) -> String { get }
      var coordinate: (Int, Int) { get }
      var labelled: (latitude: Double, longitude: Double) { get }
      var delegate: any OtherProtocol { get }
      var outcome: Result<Int, any Error> { get }
      var owner: User { get }
      var payload: Data { get }
    }
    """

    // MARK: - Resolver
    @Test(arguments: [
        "var onChangeStub: () -> Void = { }",
        "var transformStub: (Int) -> String = { _ in .init() }",
        "var coordinateStub: (Int, Int) = (.zero, .zero)",
        "var labelledStub: (latitude: Double, longitude: Double) = (latitude: .zero, longitude: .zero)",
        "var delegateStub: any OtherProtocol = OtherDouble.preview",
        "var outcomeStub: Result<Int, any Error> = .success(.zero)",
        "var ownerStub: User = User.fake()",
        "var payloadStub: Data = Data()"
    ])
    func resolver_requirementTypeIsComposite_defaultIsConstructible(_ expected: String) throws {
        let result = try PreviewableSourceGenerator.generate(from: [compositionSource])

        #expect(
            result.contains(expected),
            "Generated source must contain `\(expected)`."
        )
    }

    @Test
    func resolver_fakeHasTwoStrings_defaultsAreDistinctLoremStrings() throws {
        let generated = try PreviewableSourceGenerator.generate(from: [
            """
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
        ])
        let defaults = generated.components(separatedBy: "\n").filter {
            $0.contains("value: String = \"")
        }

        let result = defaults.count == 2
        && Set(defaults).count == 2
        && !generated.contains("LoremIpsum")

        #expect(result, "String defaults must be distinct generated LoremSwiftum strings.")
    }

    @Test
    func resolver_fakeDefaults_areDistinctAndNonZero() throws {
        let generated = try PreviewableSourceGenerator.generate(from: [
            """
            @PreviewableFake
            struct FakeDefaults {
              let firstNumber: Int
              let secondNumber: Double
              let title: String
              let detail: String
              let firstURL: URL
              let secondURL: URL
              let firstID: UUID
              let secondID: UUID
              let firstDate: Date
              let secondDate: Date
            }
            """
        ])
        let stringDefaults: [String] = generated.components(separatedBy: "\n").compactMap { line in
            guard line.contains(": String = \"") else { return .none }
            let components = line.split(separator: "\"")
            guard components.count > 1 else { return .none }
            return String(components[1])
        }
        let wordCounts = stringDefaults.map { $0.split(separator: " ").count }
        let usesDistinctURLs = generated.contains(
            "firstURL: URL = URL(string: \"https://fake.url.com/1\")!"
        ) && generated.contains(
            "secondURL: URL = URL(string: \"https://fake.url.com/2\")!"
        )
        let usesDistinctUUIDs = generated.contains(
            "firstID: UUID = UUID(uuidString: \"00000000-0000-0000-0000-000000000001\")!"
        ) && generated.contains(
            "secondID: UUID = UUID(uuidString: \"00000000-0000-0000-0000-000000000002\")!"
        )
        let usesDistinctDates = generated.contains(
            "firstDate: Date = Date(timeIntervalSince1970: 1704067200)"
        ) && generated.contains(
            "secondDate: Date = Date(timeIntervalSince1970: 1704153600)"
        )
        let result = generated.contains("firstNumber: Int = 1")
        && generated.contains("secondNumber: Double = 2")
        && usesDistinctURLs
        && usesDistinctUUIDs
        && usesDistinctDates
        && generated.contains("Generated `Date` values begin at `2024-01-01T00:00:00Z`")
        && Set(stringDefaults).count == 2
        && Set(wordCounts) == Set([2, 3])

        #expect(result, "Fake defaults must use distinct values that remain easy to identify and track.")
    }

    @Test(arguments: [
        (
            """
            struct User { let id: Int }
            @PreviewableDouble
            protocol ServiceProtocol { var user: User { get } }
            """,
            "'User' must be annotated with @PreviewableFake"
        ),
        (
            """
            protocol OtherProtocol { var flag: Bool { get } }
            @PreviewableDouble
            protocol ServiceProtocol { var other: any OtherProtocol { get } }
            """,
            "'OtherProtocol' must be annotated with @PreviewableDouble"
        ),
        (
            """
            @PreviewableDouble
            protocol ServiceProtocol { var kind: String.Type { get } }
            """,
            "cannot synthesise a default for 'String.Type'"
        ),
        (
            """
            @PreviewableFake
            struct Box<Item> { let pair: (Item, Int) }
            """,
            "cannot synthesise a default for generic parameter 'Item'"
        ),
        (
            """
            @PreviewableFake
            struct Box<Item> { let value: Item }
            @PreviewableFake
            struct Holder { let box: Box<Int> }
            """,
            "cannot synthesise a default for generic type 'Box'"
        )
    ])
    func resolver_typeCannotBeDefaulted_diagnosticNamesTheFix(
        _ source: String,
        _ expected: String
    ) {
        let message = generatorDiagnosticMessage(for: source)

        #expect(
            message?.contains(expected) == true,
            "Expected a diagnostic containing `\(expected)`, got `\(message ?? "no diagnostic")`."
        )
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
    func resolver_requirementIsEnumeration_defaultNamesACaseInScope(
        _ source: String,
        _ expected: String
    ) throws {
        let result = try PreviewableSourceGenerator.generate(from: [source])

        #expect(
            result.contains(expected),
            "The default must name a parameterless case through its enclosing types, got `\(result)`."
        )
    }
}
