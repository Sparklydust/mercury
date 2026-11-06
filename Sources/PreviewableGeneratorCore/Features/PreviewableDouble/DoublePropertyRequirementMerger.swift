//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

/// Retains a writable witness or the getter effects that satisfy every equivalent inherited property.
enum DoublePropertyRequirementMerger {

  /// Chooses a writable witness or getter effects that satisfy both equivalent property requirements.
  /// - Parameters:
  ///   - existing: The previously collected requirement.
  ///   - incoming: An equivalent inherited requirement to merge.
  static func merge(_ existing: DoubleRequirement, _ incoming: DoubleRequirement) -> DoubleRequirement {
    guard !incoming.isSettable else { return incoming }
    guard !existing.isSettable,
          var declaration = existing.declaration.decl.as(VariableDeclSyntax.self),
          var binding = declaration.bindings.first,
          let first = getter(in: binding),
          let secondBinding = incoming.declaration.decl.as(VariableDeclSyntax.self)?.bindings.first,
          let second = getter(in: secondBinding)
    else { return existing }

    var getter = first
    getter.effectSpecifiers = effects(first.effectSpecifiers, second.effectSpecifiers)
    binding.accessorBlock = AccessorBlockSyntax(accessors: .accessors([getter]))
    declaration.bindings = [binding]
    var result = existing
    result.declaration.decl = DeclSyntax(declaration)
    return result
  }

  private static func getter(in binding: PatternBindingSyntax) -> AccessorDeclSyntax? {
    guard case .accessors(let accessors) = binding.accessorBlock?.accessors else { return nil }
    return accessors.first { $0.accessorSpecifier.tokenKind == .keyword(.get) }
  }

  private static func effects(
    _ first: AccessorEffectSpecifiersSyntax?,
    _ second: AccessorEffectSpecifiersSyntax?
  ) -> AccessorEffectSpecifiersSyntax? {
    let asynchronous = first?.asyncSpecifier != nil && second?.asyncSpecifier != nil
    let failure = throwsClause(first?.throwsClause, second?.throwsClause)
    guard asynchronous || failure != nil else { return nil }
    return AccessorEffectSpecifiersSyntax(
      asyncSpecifier: asynchronous ? .keyword(.async, trailingTrivia: .space) : nil,
      throwsClause: failure
    )
  }

  private static func throwsClause(_ first: ThrowsClauseSyntax?, _ second: ThrowsClauseSyntax?) -> ThrowsClauseSyntax? {
    guard let first, let second else { return nil }
    guard let firstType = first.type else { return second }
    guard let secondType = second.type else { return first }
    return firstType.trimmedDescription == secondType.trimmedDescription ? first : nil
  }
}
