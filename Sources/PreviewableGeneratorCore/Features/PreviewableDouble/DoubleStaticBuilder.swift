//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftParser
import SwiftSyntax

/// Renders task-scoped static proxies backed by one synchronized reference per concrete double and scope.
enum DoubleStaticBuilder {

  /// Creates static proxies and their private reference-backed state.
  /// - Parameters:
  ///   - stubs: Synchronized instance storage to place inside the scoped state object.
  ///   - recordings: Actor-specific recording dictionaries.
  ///   - access: The double's effective access prefix.
  ///   - isolation: The protocol's global-actor annotation, when present.
  static func declarations(
    stubs: [String],
    recordings: [String: String],
    access: String,
    isolation: String
  ) -> [String] {
    let storage = stateStorage(stubs: stubs, recordings: recordings, access: access)
    let proxies = storage.flatMap(proxyDeclarations)
    return proxies + scopeDeclarations(storage: storage, access: access, isolation: isolation)
  }

  private static func stateStorage(
    stubs: [String],
    recordings: [String: String],
    access: String
  ) -> [String] {
    var storage = stubs
    storage.append(
      DoubleStorageBuilder.property(
        name: "calledMethods",
        type: "[String]",
        value: "[]",
        access: access + "private(set) ",
        isolated: true,
        documentation: "The static requirement invocations recorded in this scope.",
        nonisolated: true
      )
    )
    storage.append(
      DoubleStorageBuilder.property(
        name: "passedParameters",
        type: "[String: [[Any?]]]",
        value: "[:]",
        access: access + "private(set) ",
        isolated: true,
        documentation: "The static arguments recorded in the protocol's isolation, grouped by requirement.",
        sharedBacking: true
      )
    )
    storage += actorRecordingDeclarations(recordings: recordings, access: access)

    return storage
  }

  private static func proxyDeclarations(from source: String) -> [String] {
    Parser.parse(source: source).statements.compactMap { statement -> String? in
      guard let variable = statement.item.as(VariableDeclSyntax.self), let binding = variable.bindings.first,
            let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
            !name.hasPrefix("_previewable"), let type = binding.typeAnnotation?.type
      else { return nil }

      let readOnly = variable.bindingSpecifier.text == "let"
      let modifiers = variable.modifiers.trimmedDescription
      let prefix = modifiers.isEmpty ? "" : modifiers + " "
      let attributes = variable.attributes.isEmpty ? "" : variable.attributes.trimmedDescription + "\n"
      let documentation = variable.leadingTrivia.description.split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("///") }.joined(separator: "\n")
      var accessors = ["get { _previewableStaticState.\(name) }"]

      if !readOnly {
        accessors.append("set { _previewableStaticState.\(name) = newValue }")
        accessors.append("_modify { yield &_previewableStaticState.\(name) }")
      }

      return """
        \(documentation)
        /// Access requires this double's `withStaticStubs` scope.
        \(attributes)\(prefix)static var \(name): \(type.trimmedDescription) {
        \(accessors.joined(separator: "\n").indented(by: 2))
        }
        """
    }
  }

  private static func scopeDeclarations(
    storage: [String],
    access: String,
    isolation: String
  ) -> [String] {
    let state = storage.joined(separator: "\n\n").replacingOccurrences(
      of: "private var _previewable_",
      with: "fileprivate var _previewable_"
    ).replacingOccurrences(of: "private(set)", with: "fileprivate(set)")
    return [
      """
      /// Synchronized reference state shared by tasks inheriting the same static scope.
      \(isolation)private final class _PreviewableStaticState: @unchecked Sendable {
        nonisolated fileprivate let _previewableLock = NSRecursiveLock()
        nonisolated init() {}
      \(state.indented(by: 2))
      }

      /// Resolves this concrete specialization's state and traps outside its static scope.
      nonisolated private static var _previewableStaticState: _PreviewableStaticState {
        Mercury.PreviewableStaticScope.require(for: Self.self, as: _PreviewableStaticState.self)
      }

      /// Runs synchronous work with fresh static stubs and recordings.
      ///
      /// Configure responses before concurrent calls when deterministic ordering is required.
      /// - Parameter operation: All work that accesses this double's static requirements.
      /// - Throws: Errors from the operation.
      \(access)nonisolated static func withStaticStubs<Result>(_ operation: () throws -> Result) rethrows -> Result {
        try Mercury.PreviewableStaticScope.withState(
          for: Self.self, state: _PreviewableStaticState(), operation: operation
        )
      }

      /// Runs asynchronous work with fresh static state shared by inheriting child tasks.
      ///
      /// Concurrent configuration is memory-safe; ordering and queued-error assignment depend on scheduling.
      /// Detached tasks need their own scope. Nested scopes restore the previous state when work exits.
      /// - Parameter operation: All work that accesses this double's static requirements.
      /// - Throws: Errors from the operation.
      \(access)nonisolated(nonsending) static func withStaticStubs<Result>(
        _ operation: nonisolated(nonsending) () async throws -> Result
      ) async rethrows -> Result {
        try await Mercury.PreviewableStaticScope.withState(
          for: Self.self, state: _PreviewableStaticState(), operation: operation
        )
      }
      """
    ]
  }

  private static func actorRecordingDeclarations(
    recordings: [String: String],
    access: String
  ) -> [String] {
    var storage: [String] = []

    for name in recordings.keys.sorted() {
      storage.append(
        DoubleStorageBuilder.property(
          name: name,
          type: "[String: [[Any?]]]",
          value: "[:]",
          access: access + "private(set) ",
          isolated: true,
          documentation: "The static arguments recorded on this actor, grouped by requirement.",
          isolation: recordings[name] ?? ""
        )
      )
    }
    return storage
  }

}
