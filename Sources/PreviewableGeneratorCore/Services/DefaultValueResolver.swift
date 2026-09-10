//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import LoremSwiftum
import SwiftSyntax

/// Synthesises a compilable default value for a requirement type.
///
/// Resolution works on `TypeSyntax` rather than on the printed type, so tuples, closures and existentials are
/// recognised structurally instead of by string matching. Anything that cannot be defaulted correctly raises a
/// `GenerationError` naming the fix, rather than falling back to a `.init()` guess that fails to compile.
struct DefaultValueResolver {

    let index: ModuleIndex
    let context: DefaultContext

    /// Generic parameter names of the enclosing declaration, which can never be defaulted.
    var genericParameters: Set<String> = []

    /// The distinct values already emitted.
    var values = FakeDefaultValues()

    /// Returns whether the supplied type carries no value.
    static func isVoid(_ type: TypeSyntax) -> Bool {
        ["Void", "()"].contains(type.trimmedDescription)
    }

    /// Returns a compilable default expression for the supplied type.
    /// - Throws: `GenerationError` when no correct default can be synthesised.
    mutating func defaultValue(for type: TypeSyntax) throws -> String {
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return try defaultValue(for: attributed.baseType)
        }
        if type.is(OptionalTypeSyntax.self) || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return ".none"
        }
        if let function = type.as(FunctionTypeSyntax.self) {
            return try closureLiteral(for: function)
        }
        if type.is(ArrayTypeSyntax.self) { return "[]" }
        if type.is(DictionaryTypeSyntax.self) { return "[:]" }
        if let tuple = type.as(TupleTypeSyntax.self) {
            return try tupleLiteral(for: tuple)
        }
        if let existential = type.as(SomeOrAnyTypeSyntax.self) {
            return try defaultValue(for: existential.constraint)
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return try nominalDefault(
                named: member.trimmedDescription,
                simpleName: member.name.text,
                genericArguments: arguments(of: member.genericArgumentClause)
            )
        }
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return try nominalDefault(
                named: identifier.name.text,
                simpleName: identifier.name.text,
                genericArguments: arguments(of: identifier.genericArgumentClause)
            )
        }
        throw GenerationError.message(
            "cannot synthesise a default for '\(type.trimmedDescription)' — make the requirement optional"
        )
    }
}

private extension DefaultValueResolver {

    func arguments(of clause: GenericArgumentClauseSyntax?) -> [TypeSyntax] {
        clause?.arguments.compactMap { TypeSyntax($0.argument) } ?? []
    }

    mutating func closureLiteral(for function: FunctionTypeSyntax) throws -> String {
        let count = function.parameters.count
        let placeholders = Array(repeating: "_", count: count).joined(separator: ", ")
        let returnType = function.returnClause.type
        guard !Self.isVoid(returnType) else {
            return count == 0 ? "{ }" : "{ \(placeholders) in }"
        }
        let value = try defaultValue(for: returnType)
        return count == 0 ? "{ \(value) }" : "{ \(placeholders) in \(value) }"
    }

    mutating func tupleLiteral(for tuple: TupleTypeSyntax) throws -> String {
        guard !tuple.elements.isEmpty else { return "()" }
        // A single unlabelled element is a parenthesised type, not a one-element tuple.
        if tuple.elements.count == 1, let only = tuple.elements.first, only.firstName == nil {
            return try defaultValue(for: only.type)
        }
        var elements: [String] = []
        for element in tuple.elements {
            let value = try defaultValue(for: element.type)
            if let label = element.firstName?.text, label != "_" {
                elements.append("\(label): \(value)")
            } else {
                elements.append(value)
            }
        }
        return "(\(elements.joined(separator: ", ")))"
    }

    mutating func nominalDefault(
        named name: String,
        simpleName: String,
        genericArguments: [TypeSyntax]
    ) throws -> String {
        if genericParameters.contains(name) {
            throw GenerationError.message(
                "cannot synthesise a default for generic parameter '\(name)' — make the requirement optional"
            )
        }
        if let known = try knownDefault(named: name, genericArguments: genericArguments) {
            return known
        }
        if let enumDefault = index.enumDefaults[name] ?? index.enumDefaults[simpleName] {
            return enumDefault
        }
        if index.protocols[name] != nil || index.protocols[simpleName] != nil {
            return try protocolDefault(named: name, simpleName: simpleName)
        }
        if index.declaresType(name) || index.declaresType(simpleName) {
            return try ownedTypeDefault(named: name, simpleName: simpleName)
        }
        guard genericArguments.isEmpty else {
            throw GenerationError.message(
                "cannot synthesise a default for generic type '\(name)' — make the requirement optional"
            )
        }
        // Declared outside this module: trust the fake to exist, resolved through the propagated imports.
        return "\(name).fake()"
    }

    mutating func knownDefault(
        named name: String,
        genericArguments: [TypeSyntax]
    ) throws -> String? {
        switch name {
        case "Bool": return "false"
        case "String", "Substring":
            return context == .fake ? nextLoremString() : ".init()"
        case "Void": return "()"
        case "Optional": return ".none"
        case "Array", "Set", "ContiguousArray": return "[]"
        case "Dictionary": return "[:]"
        case "Date":
            return context == .fake ? nextFakeDate() : ".now"
        case "UUID":
            return context == .fake ? nextFakeUUID() : "UUID()"
        case "URL":
            return context == .fake ? nextFakeURL() : "URL(string: \"https://example.com\")!"
        case "Image": return "Image(systemName: \"photo\")"
        case "Data": return "Data()"
        case "Character": return "\"a\""
        case "Result":
            guard let success = genericArguments.first else { return nil }
            return ".success(\(try defaultValue(for: success)))"
        default:
            guard Self.numericTypes.contains(name) else { return nil }
            return context == .fake ? nextNonZeroNumber() : ".zero"
        }
    }

    func protocolDefault(named name: String, simpleName: String) throws -> String {
        guard index.annotatedProtocols[simpleName] != nil else {
            throw GenerationError.message(
                "'\(name)' must be annotated with @PreviewableDouble to be used as a requirement type"
            )
        }
        return "\(PreviewableDoubleNaming.doubleName(for: simpleName)).preview"
    }

    func ownedTypeDefault(named name: String, simpleName: String) throws -> String {
        if index.genericTypes.contains(name) || index.genericTypes.contains(simpleName) {
            throw GenerationError.message(
                "cannot synthesise a default for generic type '\(name)' — make the requirement optional"
            )
        }
        guard index.fakeAnnotatedTypes.contains(name)
                || index.fakeAnnotatedTypes.contains(simpleName)
        else {
            throw GenerationError.message(
                "'\(name)' must be annotated with @PreviewableFake to be used as a requirement type"
            )
        }
        return "\(name).fake()"
    }

    static let numericTypes: Set<String> = [
        "Double", "Float", "Float16", "Float32", "Float64", "Float80",
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "CGFloat", "TimeInterval", "Decimal"
    ]

    mutating func nextLoremString() -> String {
        for _ in 0..<100 {
            let wordCount = 2 + values.strings.count % 3
            let string = Lorem.words(wordCount)
            if values.strings.insert(string).inserted {
                return String(reflecting: string)
            }
        }
        let string = "\(Lorem.words(2)) \(values.strings.count + 1)"
        values.strings.insert(string)
        return String(reflecting: string)
    }

    mutating func nextNonZeroNumber() -> String {
        let number = (values.numbers.max() ?? 0) + 1
        values.numbers.insert(number)
        return String(number)
    }

    mutating func nextFakeURL() -> String {
        let number = (values.urls.max() ?? 0) + 1
        values.urls.insert(number)
        return "URL(string: \"https://fake.url.com/\(number)\")!"
    }

    mutating func nextFakeUUID() -> String {
        let number = (values.uuids.max() ?? 0) + 1
        values.uuids.insert(number)
        let suffix = String(repeating: "0", count: max(0, 12 - String(number).count)) + String(number)
        return "UUID(uuidString: \"00000000-0000-0000-0000-\(suffix)\")!"
    }

    mutating func nextFakeDate() -> String {
        let dayOffset = values.dates.count
        values.dates.insert(dayOffset)
        let timestamp = 1_704_067_200 + dayOffset * 86_400
        return "Date(timeIntervalSince1970: \(timestamp))"
    }
}
