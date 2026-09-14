//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// Allocates recognizable values for one generation run, respecting numeric bounds.
struct FakeDefaultValues {

  private var stringCount = 0
  private var numberCount = 0
  private var urlCount = 0
  private var uuidCount = 0
  private var dateCount = 0

  /// Returns a distinct, repeatable phrase without randomizing generated source between builds.
  mutating func string() -> String {
    let count = 2 + stringCount % 3
    var remainder = stringCount / 3
    var phrase: [String] = []
    for position in 0..<count {
      phrase.append(Self.words[(remainder % Self.words.count + position) % Self.words.count])
      remainder /= Self.words.count
    }
    if remainder > 0 { phrase.append(String(remainder)) }
    stringCount += 1
    return String(reflecting: phrase.joined(separator: " "))
  }

  private static let words = [
    "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit",
    "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "dolore",
  ]

  /// Returns a positive numeric literal, cycling within the supported bound for its type.
  /// - Parameter type: The numeric type's unqualified name.
  mutating func number(for type: String) -> String {
    let limit: Int
    switch type {
    case "Int8": limit = 127
    case "UInt8": limit = 255
    case "Int16": limit = 32_767
    case "UInt16": limit = 65_535
    case "Int32": limit = 2_147_483_647
    case "UInt32": limit = 4_294_967_295
    case "Float16": limit = 65_504
    default: limit = Int.max
    }
    numberCount = numberCount == Int.max ? 1 : numberCount + 1
    return String((numberCount - 1) % limit + 1)
  }

  /// Returns a URL construction expression with an incrementing path component.
  mutating func url() -> String {
    urlCount += 1
    return "URL(string: \"https://fake.url.com/\(urlCount)\")!"
  }

  /// Returns a UUID construction expression with an incrementing decimal suffix.
  mutating func uuid() -> String {
    uuidCount += 1
    let suffix = String(repeating: "0", count: max(0, 12 - String(uuidCount).count)) + String(uuidCount)
    return "UUID(uuidString: \"00000000-0000-0000-0000-\(suffix)\")!"
  }

  /// Returns a date expression starting at 2024-01-01 UTC and advancing one day per allocation.
  mutating func date() -> String {
    defer { dateCount += 1 }
    return "Date(timeIntervalSince1970: \(1_704_067_200 + dateCount * 86_400))"
  }
}
