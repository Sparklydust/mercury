//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Mercury
import Testing

struct PreviewableSynthesizableBehaviourTests {

  @Test
  func fake_propertyTypeIsExternal_defaultComesFromTheConformance() {
    let result = SynthesizedModel.fake().zone

    #expect(result == .gmt, "The external property must take its default from the conformance.")
  }

  @Test
  func fake_propertyTypeIsAnExternalGeneric_conformanceIsSpecialized() {
    let result = SynthesizedModel.fake().span

    #expect(result == 0..<0, "The conditional conformance must default the integer bound.")
  }

  @Test
  func fake_genericArgumentIsFloatingPoint_conformanceIsSpecialized() {
    let result = SynthesizedModel.fake().interval

    #expect(result == 0..<0, "The conditional conformance must default the floating-point bound.")
  }

  @Test
  func fake_propertyTypeIsExternal_overrideReplacesTheDefault() {
    let result = SynthesizedModel.fake(zone: TimeZone(identifier: "Europe/Zurich")!).zone

    #expect(result.identifier == "Europe/Zurich", "An override must replace the conformance default.")
  }

  @Test
  func double_requirementTypeIsExternal_stubStartsAtTheConformanceDefault() {
    let result = SynthesizedServiceDouble().zone

    #expect(result == .gmt, "The stub must start at the conformance default.")
  }

  @Test
  func double_returnTypeIsAnExternalGeneric_stubStartsAtTheConformanceDefault() {
    let result = SynthesizedServiceDouble().load()

    #expect(result == 0..<0, "The specialized stub must start at the conformance default.")
  }

  @Test
  func synthesizable_typeIsBoolean_defaultIsFalse() {
    let result = Bool.previewableDefault

    #expect(result == false, "The boolean default must be false.")
  }

  @Test
  func synthesizable_typeIsString_defaultIsEmpty() {
    let result = String.previewableDefault

    #expect(result.isEmpty, "The string default must be empty.")
  }

  @Test
  func synthesizable_typeIsCharacter_defaultIsALetter() {
    let result = Character.previewableDefault

    #expect(result == "a", "The character default must be a letter.")
  }

  @Test
  func synthesizable_typeIsData_defaultIsEmpty() {
    let result = Data.previewableDefault

    #expect(result.isEmpty, "The data default must be empty.")
  }

  @Test
  func synthesizable_typeIsDate_defaultIsTheEpoch() {
    let result = Date.previewableDefault

    #expect(result == Date(timeIntervalSince1970: 0), "The date default must be the epoch.")
  }

  @Test
  func synthesizable_typeIsUUID_defaultIsUnique() {
    let result = UUID.previewableDefault != UUID.previewableDefault

    #expect(result, "Each UUID default must be a fresh identifier.")
  }

  @Test
  func synthesizable_typeIsURL_defaultIsAbsolute() {
    let result = URL.previewableDefault

    #expect(result.absoluteString == "https://example.com", "The URL default must be an absolute address.")
  }

  @Test
  func synthesizable_typeIsDecimal_defaultIsZero() {
    let result = Decimal.previewableDefault

    #expect(result == .zero, "The decimal default must be zero.")
  }

  @Test
  func synthesizable_typeIsASignedInteger_defaultIsZero() {
    let result = [isZero(Int.self), isZero(Int8.self), isZero(Int16.self), isZero(Int32.self), isZero(Int64.self)]

    #expect(!result.contains(false), "Every signed integer default must be zero.")
  }

  @Test
  func synthesizable_typeIsAnUnsignedInteger_defaultIsZero() {
    let result = [isZero(UInt.self), isZero(UInt8.self), isZero(UInt16.self), isZero(UInt32.self), isZero(UInt64.self)]

    #expect(!result.contains(false), "Every unsigned integer default must be zero.")
  }

  @Test
  func synthesizable_typeIsFloatingPoint_defaultIsZero() {
    var result = [isZero(Double.self), isZero(Float.self), isZero(CGFloat.self)]
    #if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
    result.append(isZero(Float16.self))
    #endif

    #expect(!result.contains(false), "Every floating-point default must be zero.")
  }

  /// Returns whether the type's synthesized default is its additive identity.
  /// - Parameter _: The type whose conformance supplies the default.
  private func isZero<Value: PreviewableSynthesizable & AdditiveArithmetic>(_: Value.Type) -> Bool {
    Value.previewableDefault == .zero
  }
}
