//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import PreviewableGeneratorCore
import Testing

struct ExternalTypeDefaultTests {

  @Test
  func generator_fakePropertyTypeIsExternal_parameterDefersToConformance() throws {
    let source = "@PreviewableFake struct Model { let value: ExternalValue }"
    let expected = "value: ExternalValue = ExternalValue.previewableDefault"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "A fake property typed outside the module must defer to its conformance.")
  }

  @Test
  func generator_requirementTypeIsExternal_stubDefersToConformance() throws {
    let source = "@PreviewableDouble protocol ServiceProtocol { var kind: ExternalKind { get } }"
    let expected = "= ExternalKind.previewableDefault"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "A requirement typed outside the module must defer to its conformance.")
  }

  @Test
  func generator_returnTypeIsExternal_stubDefersToConformance() throws {
    let source = "@PreviewableDouble protocol ServiceProtocol { func load() -> ExternalKind }"
    let expected = "= ExternalKind.previewableDefault"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "A return type from outside the module must defer to its conformance.")
  }

  @Test
  func generator_closureReturnsExternalType_defaultsInsideTheClosure() throws {
    let source = "@PreviewableDouble protocol ServiceProtocol { var make: () -> ExternalKind { get } }"
    let expected = "= { ExternalKind.previewableDefault }"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "A closure must build its external result when it is called.")
  }

  @Test
  func generator_tupleHoldsExternalType_defaultsTheElement() throws {
    let source = "@PreviewableDouble protocol ServiceProtocol { var pair: (ExternalKind, Int) { get } }"
    let expected = "= (ExternalKind.previewableDefault, .zero)"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "Each tuple element typed outside the module must defer to its conformance.")
  }

  @Test
  func generator_resultSucceedsWithExternalType_defaultsTheSuccessValue() throws {
    let source = "@PreviewableDouble protocol ServiceProtocol { var kind: Result<ExternalKind, Error> { get } }"
    let expected = "= .success(ExternalKind.previewableDefault)"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "A result's external success value must defer to its conformance.")
  }

  @Test
  func generator_genericTypeIsExternal_defersToConformanceWithItsArguments() throws {
    let source = "@PreviewableDouble protocol ServiceProtocol { var box: ExternalBox<Int> { get } }"
    let expected = "= ExternalBox<Swift.Int>.previewableDefault"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "An external generic type must defer to its specialized conformance.")
  }

  @Test
  func generator_optionalTypeIsExternal_staysNone() throws {
    let source = "@PreviewableDouble protocol ServiceProtocol { var kind: ExternalKind? { get } }"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(!result.contains("previewableDefault"), "An optional typed outside the module must keep its empty default.")
  }

  @Test
  func generator_arrayElementIsExternal_staysEmpty() throws {
    let source = "@PreviewableDouble protocol ServiceProtocol { var kinds: [ExternalKind] { get } }"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(!result.contains("previewableDefault"), "An array typed outside the module must keep its empty default.")
  }

  @Test
  func generator_existentialProtocolIsLocal_resolvesToTheDouble() throws {
    let source = """
      @PreviewableDouble protocol ItemProtocol { var value: Int { get } }
      @PreviewableDouble protocol ServiceProtocol { var item: any ItemProtocol { get } }
      """
    let expected = "= ItemDouble()"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "An existential of a protocol the module declares must still use its double.")
  }

  @Test
  func generator_responseIsAnAssociatedType_staysUnconfigured() throws {
    let source = "@PreviewableDouble protocol ServiceProtocol { associatedtype Item\nvar item: Item { get } }"
    let expected = "Mercury.PreviewableValue<_PreviewableItem> = .unconfigured"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "An associated-type response must stay unconfigured for every specialization.")
  }

  @Test
  func generator_qualifiedGenericTypeIsExternal_rendersArgumentsOnce() throws {
    let source = "@PreviewableDouble protocol ServiceProtocol { var box: Outer.Inner<Int> { get } }"
    let expected = "= Outer.Inner<Swift.Int>.previewableDefault"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "A qualified external generic type must render its arguments once.")
  }
}
