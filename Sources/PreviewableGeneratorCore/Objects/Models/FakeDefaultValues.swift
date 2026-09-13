import LoremSwiftum

/// Allocates recognizable values for one generation run, respecting numeric bounds.
struct FakeDefaultValues {
  private var strings: Set<String> = []
  private var numberCount = 0
  private var urlCount = 0
  private var uuidCount = 0
  private var dateCount = 0

  mutating func string() -> String {
    for _ in 0..<100 {
      let value = Lorem.words(2 + strings.count % 3)
      if strings.insert(value).inserted { return String(reflecting: value) }
    }
    let value = "\(Lorem.words(2)) \(strings.count + 1)"
    strings.insert(value)
    return String(reflecting: value)
  }

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

  mutating func url() -> String {
    urlCount += 1
    return "URL(string: \"https://fake.url.com/\(urlCount)\")!"
  }

  mutating func uuid() -> String {
    uuidCount += 1
    let suffix = String(repeating: "0", count: max(0, 12 - String(uuidCount).count)) + String(uuidCount)
    return "UUID(uuidString: \"00000000-0000-0000-0000-\(suffix)\")!"
  }

  mutating func date() -> String {
    defer { dateCount += 1 }
    return "Date(timeIntervalSince1970: \(1_704_067_200 + dateCount * 86_400))"
  }
}
