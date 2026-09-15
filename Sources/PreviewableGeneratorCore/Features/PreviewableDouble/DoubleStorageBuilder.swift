//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import SwiftSyntax

/// Renders synchronized storage without changing the names used to configure a double.
enum DoubleStorageBuilder {

  /// Renders backing storage and accessors synchronized by the double's recursive lock.
  /// - Parameters:
  ///   - name: The exposed configuration or recording property name.
  ///   - type: The Swift type spelling of the stored value.
  ///   - value: The initial expression, or `nil` for a response that requires explicit configuration.
  ///   - access: Access modifiers, including any required trailing space.
  ///   - isolated: Whether setter assignments may omit the `Sendable` check.
  ///   - documentation: The summary attached to the exposed property, without a comment marker.
  ///   - isolation: Global-actor attributes applied to both storage and its accessors.
  ///   - nonisolated: Whether the accessors must be callable outside the double's actor.
  ///   - sharedBacking: Whether locked backing storage accepts writes from multiple actors.
  static func property(
    name: String,
    type: String,
    value: String?,
    access: String,
    isolated: Bool,
    documentation: String? = nil,
    isolation: String = "",
    nonisolated: Bool = false,
    sharedBacking: Bool = false
  ) -> String {
    let check = isolated ? "" : "previewableRequireSendable(newValue)\n"
    let comment = documentation.map { "/// \($0)\n" } ?? ""
    let backing = nonisolated || sharedBacking ? "nonisolated(unsafe) " : ""
    let modifier = nonisolated ? "nonisolated " : ""
    let storageType = value == nil ? "Mercury.PreviewableValue<\(type)>" : type
    let initial = value ?? ".unconfigured"
    let read = value == nil ? "_previewable_\(name).require(\(String(reflecting: name)))" : "_previewable_\(name)"
    let assignment = value == nil ? ".configured(newValue)" : "newValue"
    let modification =
      value == nil
      ? "var value = \(read)\n    defer { _previewable_\(name) = .configured(value) }\n    yield &value"
      : "yield &_previewable_\(name)"
    return """
      \(isolation)\(backing)private var _previewable_\(name): \(storageType) = \(initial)
      \(comment)\(isolation)\(access)\(modifier)var \(name): \(type) {
        get { _previewableLock.withLock { \(read) } }
        set {
      \(check.indented(by: 4))    _previewableLock.withLock { _previewable_\(name) = \(assignment) }
        }
        _modify {
          _previewableLock.lock()
          defer { _previewableLock.unlock() }
          \(modification)
        }
      }
      """
  }

  /// Returns the recording dictionary that keeps an explicitly isolated requirement's arguments on its actor.
  /// - Parameter isolation: The requirement's qualified actor attribute, or an empty string.
  static func recordingName(for isolation: String) -> String {
    guard !isolation.isEmpty else { return "passedParameters" }
    let actor = isolation.trimmingCharacters(in: .whitespacesAndNewlines)
      .dropFirst().replacingOccurrences(of: ".", with: "_")
    return actor.lowercasingFirstCharacter + "PassedParameters"
  }

  /// Returns global-actor attributes with trailing newlines, or an empty string for nonisolated declarations.
  /// - Parameters:
  ///   - attributes: Attributes on the protocol or requirement.
  ///   - index: Global actors available in the module.
  ///   - scope: Enclosing type names used to resolve an unqualified actor.
  static func isolationAttributes(
    in attributes: AttributeListSyntax,
    index: ModuleIndex,
    scope: [String] = []
  ) -> String {
    attributes.compactMap { element -> String? in
      guard case .attribute(let attribute) = element else { return nil }
      let name = attribute.attributeName.trimmedDescription
      let resolved = index.resolve(name, scope: scope) ?? name
      guard
        ["MainActor", "Swift.MainActor", "_Concurrency.MainActor"].contains(name)
          || index.globalActors.contains(resolved)
      else { return nil }
      return attribute.trimmedDescription + "\n"
    }.joined()
  }

  /// Recognizes explicit global-actor isolation, including inherited protocol isolation.
  /// - Parameters:
  ///   - declaration: The protocol to inspect.
  ///   - index: Protocol and global-actor declarations available in the module.
  ///   - visited: Qualified protocol names already inspected during recursive lookup.
  static func isIsolated(
    _ declaration: ProtocolDeclSyntax,
    index: ModuleIndex,
    visited: Set<String> = []
  ) -> Bool {
    let name = index.protocols.first { $0.value.id == declaration.id }?.key ?? declaration.name.text
    let scope = name.split(separator: ".").map(String.init)
    guard !visited.contains(name) else { return false }
    if !isolationAttributes(in: declaration.attributes, index: index, scope: scope).isEmpty {
      return true
    }
    return (declaration.inheritanceClause?.inheritedTypes ?? []).contains {
      guard let resolved = index.resolve($0.type.trimmedDescription, scope: scope),
        let base = index.protocols[resolved]
      else { return false }
      return isIsolated(base, index: index, visited: visited.union([name]))
    }
  }
}
