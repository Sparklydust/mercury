//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

/// Captures responses and errors synchronously before awaiting user observation or a call pause.
enum DoubleAsyncInvocationBuilder {

  /// Renders a locked response snapshot followed by observation and any per-call pause.
  /// - Parameters:
  ///   - invocation: Recording and response-selection statements run under the double's lock.
  ///   - receiver: The instance or scoped static state that owns the lock.
  ///   - stub: The base name of this member's response and spy storage.
  ///   - output: The declared return type, including `Void` for valueless calls.
  ///   - failure: The declared error type, or `nil` for a nonthrowing response.
  static func body(
    invocation: [String],
    receiver: String,
    stub: String,
    output: String,
    failure: String?
  ) -> String {
    let snapshot = snapshot(invocation: invocation, output: output, failure: failure)
    return """
      let response: \(responseType(output: output, failure: failure)) = Mercury.previewableWithLock(\(receiver)._previewableLock) {
      \(snapshot.indented(by: 2))
      }
      await self.\(stub)Spy.recordCall()
      return \(failure == nil ? "response" : "try response.get()")
      """
  }

  private static func responseType(output: String, failure: String?) -> String {
    failure.map { "Swift.Result<\(output), \($0)>" } ?? output
  }

  private static func snapshot(invocation: [String], output: String, failure: String?) -> String {
    guard let failure else { return invocation.joined(separator: "\n") }
    return """
      Swift.Result { () throws(\(failure)) -> \(output) in
      \(invocation.joined(separator: "\n").indented(by: 2))
      }
      """
  }
}
