//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

/// Captures responses and errors synchronously before awaiting user observation or a call pause.
enum DoubleAsyncInvocationBuilder {

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
