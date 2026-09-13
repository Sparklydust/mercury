import SwiftSyntax

/// Renders synchronized storage without changing the names used to configure a double.
enum DoubleStorageBuilder {
  static func property(name: String, type: String, value: String, access: String, isolated: Bool) -> String {
    let check = isolated ? "" : "previewableRequireSendable(newValue)\n"
    return """
      private var _previewable_\(name): \(type) = \(value)
      \(access)var \(name): \(type) {
        get { _previewableLock.withLock { _previewable_\(name) } }
        set {
      \(check.indented(by: 4))    _previewableLock.withLock { _previewable_\(name) = newValue }
        }
        _modify {
          _previewableLock.lock()
          defer { _previewableLock.unlock() }
          yield &_previewable_\(name)
        }
      }
      """
  }

  /// Recognizes explicit global-actor isolation, including inherited protocol isolation.
  static func isIsolated(_ declaration: ProtocolDeclSyntax, index: ModuleIndex, visited: Set<String> = []) -> Bool {
    let name = index.protocols.first { $0.value.id == declaration.id }?.key ?? declaration.name.text
    let scope = name.split(separator: ".").map(String.init)
    guard !visited.contains(name) else { return false }
    if declaration.attributes.contains(where: {
      guard case .attribute(let attribute) = $0 else { return false }
      let attributeName = attribute.attributeName.trimmedDescription
      if ["MainActor", "Swift.MainActor", "_Concurrency.MainActor"].contains(attributeName) { return true }
      guard let resolved = index.resolve(attributeName, scope: scope) else { return false }
      return index.globalActors.contains(resolved)
    }) {
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
