#!/usr/bin/env python3
#
# Copyright © 2026 Mercury contributors. MIT licensed.
#
"""Compile and execute generated consumers in disposable directories."""
import argparse
import json
import os
import platform
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--products', type=Path, required=True)
parser.add_argument('--swiftc', default='swiftc')
parser.add_argument('--generator', type=Path, default=Path(__file__).resolve().parents[1] /
  'Artifacts/PreviewableGenerator.artifactbundle/bin/PreviewableGenerator')
args = parser.parse_args()
products = args.products.resolve()
generator = args.generator.resolve()
plugin = products / 'PreviewableMacrosPlugin'
if not plugin.exists():
  plugin = products / 'PreviewableMacrosPlugin-tool'
modules = products if (products / 'Mercury.swiftmodule').exists() else products / 'Modules'
link = ['-L', str(products), '-lMercury'] if (products / 'libMercury.a').exists() else [
  str(path) for path in sorted((products / 'Mercury.build').glob('*.swift.o'))]
assert generator.exists() and plugin.exists() and link, 'Build the package tests before verifying consumers'


def run(command, **options):
  return subprocess.run(command, capture_output=True, text=True, timeout=120, **options)


def require_success(result, name):
  if result.returncode:
    raise AssertionError(f'{name}:\n{result.stdout}\n{result.stderr}')


with tempfile.TemporaryDirectory(prefix='mercury-consumers-') as directory:
  root = Path(directory)
  # Match Package.swift rather than swiftc's deployment target for the build host.
  compiler = [args.swiftc, '-swift-version', '6']
  if platform.system() == 'Darwin':
    compiler += ['-target', f'{platform.machine()}-apple-macosx27.0']
  base = compiler + ['-I', str(modules),
    '-module-cache-path', str(root / 'cache'),
    '-load-plugin-executable', f'{plugin}#PreviewableMacrosPlugin']

  for annotation, declaration, diagnostic in [
    ('PreviewableDouble', 'struct Model {}', 'can only be applied to a protocol'),
    ('PreviewableFake', 'enum Model {}', 'can only be applied to a structure, a class')
  ]:
    source = root / (annotation + '.swift')
    source.write_text('import Mercury\n@' + annotation + '\n' + declaration)
    result = run(base + ['-typecheck', str(source)])
    assert result.returncode != 0 and diagnostic in result.stderr, result.stderr
    print('PASS bundled-macro-diagnostic-' + annotation, flush=True)

  incremental = root / 'incremental'
  incremental.mkdir()
  original = incremental / 'Model.swift'
  unrelated = incremental / 'Other.swift'
  generated = incremental / 'Generated.swift'
  original.write_text('import Mercury\n@PreviewableFake struct Model { let name: String }')
  unrelated.write_text('func unrelated() -> Int { 0 }')
  command = [str(generator), str(generated), str(original), str(unrelated)]
  require_success(run(command), 'initial generation')
  expected = generated.read_bytes()
  modified = generated.stat().st_mtime_ns
  require_success(run(command), 'unchanged generation')
  assert generated.stat().st_mtime_ns == modified, 'unchanged output was rewritten'
  print('PASS unchanged-output-preserves-timestamp', flush=True)
  require_success(run(command[:2] + list(reversed(command[2:]))), 'reordered inputs')
  assert generated.stat().st_mtime_ns == modified, 'input ordering invalidated output'
  print('PASS reordered-inputs-preserve-output', flush=True)
  unrelated.write_text('func unrelated() -> Int { 1 }')
  require_success(run(command), 'unrelated edit')
  assert generated.stat().st_mtime_ns == modified, 'unrelated edit invalidated output'
  print('PASS unrelated-edit-preserves-output', flush=True)
  generated.write_text('corrupted output')
  require_success(run(command), 'output repair')
  assert generated.read_bytes() == expected, 'modified generated output was not repaired'
  print('PASS corrupted-output-is-repaired', flush=True)
  original_stat = original.stat()
  original.write_text('import Mercury\n@PreviewableFake struct Model { let role: String }')
  os.utime(original, ns=(original_stat.st_atime_ns, original_stat.st_mtime_ns))
  require_success(run(command), 'changed annotation')
  assert b'role: String' in generated.read_bytes(), 'changed inputs reused stale output'
  print('PASS changed-inputs-invalidate-cache', flush=True)

  long_path = incremental
  for index in range(4):
    long_path /= str(index) + 'x' * 199
  long_path.mkdir(parents=True)
  empty = long_path / 'Empty.swift'
  empty.write_text('// No declarations.\n')
  inputs = [str(empty)] * (os.sysconf('SC_ARG_MAX') // len(str(empty)) + 1) + [str(original)]
  input_list = incremental / 'Inputs.json'
  input_list.write_text(json.dumps(inputs))
  assert input_list.stat().st_size > os.sysconf('SC_ARG_MAX')
  require_success(run([str(generator), str(generated), '--input-file-list', str(input_list)]), 'large input list')
  assert b'role: String' in generated.read_bytes(), 'large input list lost annotated sources'
  print('PASS input-list-exceeds-command-line-limit', flush=True)

  def verify(name, source, main='', release=False, compile_error=None, crashes=False, flags=(), generation_error=None):
    folder = root / name
    folder.mkdir()
    originals = []
    for index, text in enumerate([source] if isinstance(source, str) else source):
      original = folder / f'Model{index}.swift'
      original.write_text('import Mercury\n' + text)
      originals.append(str(original))
    generated = folder / 'Generated.swift'
    input_list = folder / 'Inputs.json'
    input_list.write_text(json.dumps(originals))
    generation = run([str(generator), str(generated), '--input-file-list', str(input_list)])
    if generation_error:
      assert generation.returncode != 0 and generation_error in generation.stderr, name + ': ' + generation.stderr
      print('PASS', name, flush=True)
      return None
    require_success(generation, name + ' generation')
    sources = originals + [str(generated)]
    if main:
      entry = folder / 'main.swift'
      entry.write_text('import Foundation\nimport Mercury\n' + main)
      sources.append(str(entry))
    output = folder / ('consumer' if main else 'Consumer.o')
    command = base + ([] if release else ['-D', 'DEBUG']) + list(flags)
    command += sources + (link + ['-o', str(output)] if main else ['-c', '-whole-module-optimization', '-o', str(output)])
    result = run(command)
    if compile_error:
      assert result.returncode != 0 and compile_error in result.stderr, name + ': ' + result.stderr
    else:
      require_success(result, name + ' compilation')
      if main:
        result = run([str(output)])
        if crashes:
          expected = crashes if isinstance(crashes, str) else 'Missing Previewable response'
          assert result.returncode != 0 and expected in result.stderr, name + ': ' + result.stderr
        else:
          require_success(result, name + ' execution')
    print('PASS', name, flush=True)
    return output

  legacy = ('final class Payload { var value = 0 }\n'
    '@PreviewableDouble protocol Legacy { var payload: Payload? { get set }; '
    'func store(_ value: Payload) -> Payload?; init(payload: Payload); '
    'subscript(_ value: Payload) -> Payload? { get set } }')
  verify('legacy-non-sendable-values', legacy,
    'let payload = Payload(); let double = LegacyDouble(payload: payload); '
    'double.payload = payload; double.storeStub = payload; double.subscriptStub = payload; '
    'precondition(double.payload === payload); precondition(double.store(payload) === payload); '
    'precondition(double[payload] === payload); double[payload] = payload; '
    'precondition(double.calledMethods.count == 4)')
  verify('legacy-release-signatures', legacy, release=True)
  verify('legacy-fresh-nonisolated-previews', legacy,
    'nonisolated func check() { let first = LegacyDouble.preview; let second = legacyDouble; '
    'first.payload = Payload(); precondition(first !== second); precondition(second.payload == nil) }; check()')
  verify('legacy-main-actor-default', legacy, flags=('-default-isolation', 'MainActor'))
  verify('legacy-generic-response',
    'final class Payload {}\n@PreviewableDouble protocol Legacy { func load<Value>(_ type: Value.Type) -> Value }',
    'let payload = Payload(); let double = LegacyDouble(); double.loadStub.set(payload, for: Payload.self); '
    'precondition(double.load(Payload.self) === payload)')
  legacy_generic = ('final class Payload {}\n'
    '@PreviewableDouble protocol Legacy { func load<Value>(_ type: Value.Type) -> Value }')
  verify('legacy-generic-optional-nil', legacy_generic,
    'let double = LegacyDouble(); double.loadStub.set(nil, for: Payload?.self); '
    'precondition(double.load(Payload?.self) == nil)')
  verify('legacy-generic-removed-response', legacy_generic,
    'let double = LegacyDouble(); double.loadStub.set(Payload(), for: Payload.self); '
    'double.loadStub.remove(for: Payload.self); let _: Payload = double.load(Payload.self)', crashes=True)
  verify('legacy-generic-main-actor-default', legacy_generic, flags=('-default-isolation', 'MainActor'))
  verify('actor-isolated-generic-response',
    'final class Payload {}\n'
    '@MainActor @PreviewableDouble protocol Legacy { func load<Value>(_ type: Value.Type) -> Value }',
    '@MainActor func check() { let payload = Payload(); let double = LegacyDouble(); '
    'double.loadStub.set(payload, for: Payload.self); precondition(double.load(Payload.self) === payload) }; check()')
  verify('legacy-associated-response',
    'final class Payload {}\n@PreviewableDouble protocol Legacy<Value> { associatedtype Value; func load() -> Value }',
    'let payload = Payload(); let double = LegacyDouble<Payload>(); double.loadStub = payload; '
    'precondition(double.load() === payload)')
  verify('legacy-nested-protocol',
    '@PreviewableDouble protocol Child { var value: Int { get set } }\n'
    '@PreviewableDouble protocol Legacy { var child: any Child { get } }',
    'let double = LegacyDouble(); precondition(double.child.value == 0)')
  verify('legacy-closures',
    'final class Payload { var value = 7 }\ntypealias Callback = (Payload) -> Void\n'
    '@PreviewableDouble protocol Legacy { var callback: Callback { get set }; '
    'func observe(_ callback: Callback); init(callback: Callback); func make() -> () -> Payload? }',
    'let double = LegacyDouble(callback: { _ in }); let payload = Payload(); '
    'double.callback = { $0.value += 1 }; double.callback(payload); double.observe { _ in }; '
    'double.makeStub = { payload }; precondition(double.make()() === payload); '
    'precondition(payload.value == 8); precondition(double.passedParameters["observe(_:)"]?.first?.isEmpty == true)')
  verify('legacy-double-is-not-sendable', '@PreviewableDouble protocol Legacy {}',
    'func requireSendable<Value: Sendable>(_ value: Value) {}\nrequireSendable(LegacyDouble())',
    compile_error='Sendable')
  for number, inheritance in enumerate([': Sendable', ': Swift.Sendable', ': Base', 'where Self: Sendable']):
    verify('sendable-shared-preview-' + str(number),
      'protocol Base: Sendable {}\n@PreviewableDouble protocol Service ' + inheritance + ' {}',
      'func requireSendable<Value: Sendable>(_ value: Value) {}\n'
      'requireSendable(ServiceDouble.preview); precondition(ServiceDouble.preview === serviceDouble)')

  for condition in ['os(macOS)', 'os(iOS)', 'DEBUG']:
    verify('conditional-requirement-' + condition,
      '@PreviewableDouble protocol Service {\n#if ' + condition + '\nfunc refresh()\n#endif\n}',
      generation_error="conditional requirements in 'Service'")
  verify('inherited-conditional-requirement',
    'protocol Base {\n#if os(macOS)\nfunc refresh()\n#endif\n}\n'
    '@PreviewableDouble protocol Service: Base {}', generation_error="conditional requirements in 'Base'")
  for number, declaration in enumerate([
    'let serviceDouble = 42', 'let (serviceDouble, other) = (1, 2)', 'private let `serviceDouble` = 42',
    'func serviceDouble() -> Int { 1 }', 'struct serviceDouble {}', '@PreviewableDouble protocol service {}',
  ]):
    verify('accessor-collision-' + str(number), [declaration, '@PreviewableDouble protocol Service {}'],
      generation_error="generated name 'serviceDouble' conflicts")
  verify('accessor-name-in-other-scopes',
    'struct Scope { let serviceDouble = 1 }\nfunc serviceDouble(_ value: Int) -> Int { value }\n'
    '@PreviewableDouble protocol Service {}')
  verify('generic-double-with-global-name',
    'let serviceDouble = 1\n@PreviewableDouble protocol Service { associatedtype Value; func load() -> Value }')
  alias_source = ('typealias Count = Int\ntypealias Total = Count\n'
    '@PreviewableFake struct Model { let count: Total }\n'
    '@PreviewableDouble protocol Service { func count() -> Total }')
  verify('alias-fake-and-double', alias_source,
    'precondition(Model.fake().count > 0)\nprecondition(ServiceDouble().count() == 0)')
  verify('alias-release-signature', alias_source, release=True)
  verify('alias-lexical-scope',
    'typealias Value = String\nenum Domain { typealias Value = Int; typealias Count = Value; '
    '@PreviewableFake struct Model { typealias Value = Bool; let count: Count } }',
    'precondition(Domain.Model.fake().count > 0)')
  verify('alias-closure-storage',
    'typealias Action = () -> Int\n@PreviewableFake struct Model { let action: Action }\n'
    '@PreviewableFake final class Reference { var action: Action = { 0 }; init() {} }',
    'precondition(Model.fake().action() > 0)\nprecondition(Reference.fake().action() > 0)')
  verify('alias-optional-recursion',
    'typealias Next = Model?\n@PreviewableFake final class Model { var next: Next = nil; init() {} }',
    'precondition(Model.fake().next == nil)')
  verify('alias-eager-recursion',
    'typealias Next = Model\n@PreviewableFake final class Model { var next: Next; init() { fatalError() } }',
    generation_error='recursive default construction')
  verify('alias-cycle', 'typealias A = B\ntypealias B = A\n@PreviewableFake struct Model { let value: A }',
    generation_error='cyclic type alias')
  alias_throwing = ('@PreviewableFake struct Leaf { let value: Int; init(value: Int) throws { self.value = value } }\n'
    'typealias Item = Leaf\n@PreviewableFake struct Model { let leaf: Item }')
  verify('alias-throwing-default', alias_throwing, 'let value = try Model.fake()\nprecondition(value.leaf.value > 0)')
  verify('alias-throwing-release', alias_throwing, release=True)
  for name in ['repeat', 'class', 'default', 'self']:
    source = '@PreviewableFake struct Model { let `' + name + '`: Int }'
    verify('stored-keyword-' + name, source, 'precondition(Model.fake().' + '`' + name + '` > 0)')
    verify('stored-keyword-release-' + name, source, release=True)
    source = ('struct Model { let `' + name + '`: Int }\n'
      '@PreviewableFake(parameters: [("' + name + '", Int.self)]) extension Model {}')
    verify('external-keyword-' + name, source, 'precondition(Model.fake().' + '`' + name + '` > 0)')
    verify('external-keyword-release-' + name, source, release=True)

  for number, initializer in enumerate(['init(token: Int) {}', 'init() throws {}']):
    verify('inherited-initializer-' + str(number),
      'class Base { ' + initializer + ' }\n@PreviewableFake final class Model: Base { var value = 0 }',
      generation_error="cannot verify inherited 'init()'")
  for throwing in [False, True]:
    effects = ' throws' if throwing else ''
    call = 'try ' if throwing else ''
    verify('explicit-subclass-initializer-' + str(throwing),
      'class Base { init(token: Int)' + effects + ' {} }\n'
      '@PreviewableFake final class Model: Base { var value = 0; init()' + effects + ' { ' + call + 'super.init(token: 1) } }',
      'let value = ' + call + 'Model.fake(value: 42)\nprecondition(value.value == 42)')
  verify('class-with-protocol-conformance',
    'protocol Named {}\n@PreviewableFake final class Model: Named { var value = 0 }',
    'precondition(Model.fake(value: 42).value == 42)')
  for number, alias in enumerate(['typealias ServiceDouble = Int', 'typealias ServiceDouble<Value> = [Value]']):
    verify('double-alias-collision-' + str(number), alias + '\n@PreviewableDouble protocol Service {}',
      generation_error="generated type 'ServiceDouble' conflicts")
  verify('nested-double-alias', 'enum Scope { typealias ServiceDouble = Int }\n@PreviewableDouble protocol Service {}')
  for number, signature in enumerate(['<Value>() -> Value', '<Value: Codable>() -> [Value]']):
    verify('unconstrained-generic-response-' + str(number),
      '@PreviewableDouble protocol ServiceProtocol: Sendable { func make' + signature + ' }',
      generation_error='requires a Sendable constraint')
  for number, signature in enumerate([
    '<Value: Sendable>() -> Value', '<Value>() -> Value where Value: Swift.Sendable',
    '<Value: Codable & Sendable>() -> [Value]', '<Value: Transferable>() -> Value?',
  ]):
    verify('constrained-generic-response-' + str(number),
      'protocol Transferable: Sendable {}\n@PreviewableDouble protocol ServiceProtocol: Sendable { func make' + signature + ' }')
  for actor in ['MainActor', 'Context', 'Scope.Context']:
    actor_source = (
      '@globalActor actor Context { static let shared = Context() }\n'
      'enum Scope { @globalActor actor Context { static let shared = Context() } }\n'
      'final class Payload { var value = 0 }\n@PreviewableDouble protocol ServiceProtocol {\n'
      '  @' + actor + ' var payload: Payload? { get set }\n'
      '  @' + actor + ' func store(_ value: Payload) -> Payload?\n'
      '  @' + actor + ' init(value: Payload)\n'
      '  func count() -> Int\n}')
    verify('requirement-actor-' + actor, actor_source)
    verify('requirement-stub-isolation-' + actor, actor_source,
      'nonisolated func configure(_ double: ServiceDouble) { double.payloadStub = Payload() }',
      compile_error='isolated property')
    recording = actor[0].lower() + actor[1:].replace('.', '_') + 'PassedParameters'
    verify('requirement-recording-isolation-' + actor, actor_source,
      'nonisolated func read(_ double: ServiceDouble) { _ = double.' + recording + ' }',
      compile_error='isolated property')
    verify('recorded-argument-cannot-be-transferred-' + actor, actor_source,
      '@' + actor + ' func transfer(_ double: ServiceDouble) { '
      'let value = double.' + recording + '["store(_:)"]![0][0] as! Payload; '
      'Task.detached { value.value += 1 } }', compile_error='race')
    verify('requirement-recording-access-' + actor, actor_source,
      '@' + actor + ' func check() { let double = ServiceDouble(); let value = Payload(); '
      'double.store(value); precondition((double.' + recording + '["store(_:)"]![0][0] as! Payload) === value); '
      'precondition(double.passedParameters.isEmpty) }')
  verify('nonisolated-requirements-on-actor-protocol',
    '@MainActor @PreviewableDouble protocol ServiceProtocol { '
    'nonisolated var count: Int { get set }; nonisolated func name() -> String }',
    'nonisolated func check() { let double = ServiceDouble(); double.count = 42; '
    'double.nameStub = "ready"; precondition(double.name() == "ready"); precondition(double.count == 42) }\ncheck()')
  verify('mixed-actors',
    '@globalActor actor Context { static let shared = Context() }\nfinal class Payload {}\n'
    '@PreviewableDouble protocol ServiceProtocol: Sendable { '
    '@MainActor func store(_ value: Payload); @Context func cache(_ value: Payload); func load(id: Int) }')
  verify('actor-recording-name-collision',
    '@PreviewableDouble protocol ServiceProtocol { @MainActor func store(); var mainActorPassedParameters: Int { get } }',
    generation_error='conflicts with a generated member')
  verify('generic-associated-response-needs-constraint',
    '@PreviewableDouble protocol ServiceProtocol: Sendable { func first<T: Collection & Sendable>(_ values: T) -> T.Element }',
    generation_error="generic response 'T.Element'")
  verify('generic-associated-response-is-constrained',
    '@PreviewableDouble protocol ServiceProtocol: Sendable { '
    'func first<T: Collection & Sendable>(_ values: T) -> T.Element where T.Element: Sendable }')
  verify('generic-closure-response-needs-sendable',
    '@PreviewableDouble protocol ServiceProtocol: Sendable { func make<T: Sendable>(_ value: T) -> () -> T }',
    generation_error='requires @Sendable')
  for attribute in ['Sendable', 'MainActor']:
    verify('generic-closure-response-' + attribute,
      '@PreviewableDouble protocol ServiceProtocol: Sendable { func make<T: Sendable>(_ value: T) -> @' + attribute + ' () -> T }')
  verify('inherited-requirement-actor',
    'final class Payload {}\nenum Scope {\n'
    '  @globalActor actor Context { static let shared = Context() }\n'
    '  protocol Base { @Context func store(_ value: Payload) }\n'
    '}\n@PreviewableDouble protocol ServiceProtocol: Scope.Base {}')

  associated = ('@PreviewableDouble protocol ServiceProtocol<Value>: Sendable { '
    'associatedtype Value: Sendable; func load() -> Value; static func fetch() -> Value }')
  verify('associated-explicit-nil', associated,
    'let double = ServiceDouble<String?>(); double.loadStub = nil; precondition(double.load() == nil)')
  verify('missing-associated-response', associated, 'let _ = ServiceDouble<String>().load()', crashes=True)
  verify('associated-release', associated, release=True)
  verify('primary-associated-type-injection', associated,
    'let double = ServiceDouble<String>(); double.loadStub = "ready"; '
    'let service: any ServiceProtocol<String> = double; precondition(service.load() == "ready")')
  static = '@PreviewableDouble protocol ServiceProtocol: Sendable { static func load() -> Int }'
  verify('static-missing-scope', static, 'let _ = ServiceDouble.load()', crashes='Missing Previewable static scope')
  verify('static-scope-ends', static,
    'ServiceDouble.withStaticStubs { ServiceDouble.loadStub = 42 }; let _ = ServiceDouble.load()',
    crashes='Missing Previewable static scope')
  verify('static-detached-needs-scope', static,
    'await ServiceDouble.withStaticStubs { await Task.detached { ServiceDouble.load() }.value }',
    crashes='Missing Previewable static scope')
  verify('static-detached-explicit-scope', static,
    'let value = await Task.detached { ServiceDouble.withStaticStubs { '
    'ServiceDouble.loadStub = 42; return ServiceDouble.load() } }.value; precondition(value == 42)')
  verify('static-actor-associated-payload',
    'final class Payload {}\n@MainActor @PreviewableDouble protocol ServiceProtocol<Value> { '
    'associatedtype Value; static func store(_ value: Value) -> Value? }',
    '@MainActor func check() async { await ServiceDouble<Payload>.withStaticStubs { '
    'let payload = Payload(); ServiceDouble<Payload>.storeStub = payload; await Task.yield(); '
    'precondition(ServiceDouble<Payload>.store(payload) === payload) } }; await check()')
  for actor in ['MainActor', 'Context']:
    source = ('@globalActor actor Context { static let shared = Context() }\nfinal class Payload {}\n'
      '@PreviewableDouble protocol ServiceProtocol { @' + actor + ' static func load() -> Payload? }')
    verify('static-member-actor-' + actor, source)
    verify('static-stub-isolation-' + actor, source,
      'nonisolated func configure() { ServiceDouble.loadStub = Payload() }', compile_error='isolated static property')
  verify('static-non-sendable-argument',
    'final class Payload {}\n@PreviewableDouble protocol ServiceProtocol { static func store(_ value: Payload) }',
    compile_error='Sendable')
  verify('static-generic-response',
    '@PreviewableDouble protocol ServiceProtocol: Sendable { '
    'static func make<Value: Sendable>(_ type: Value.Type) -> Value }',
    'ServiceDouble.withStaticStubs { ServiceDouble.makeStub.set(42, for: Int.self); '
    'let value: Int = ServiceDouble.make(Int.self); precondition(value == 42) }')
  verify('async-spy-observation',
    '@PreviewableDouble protocol ServiceProtocol: Sendable { func load() async -> Int }',
    '@MainActor func check() async { let double = ServiceDouble(); var observed: Int?; '
    'double.loadSpy.observe { [weak double] in observed = double?.calledMethods.count }; '
    '_ = await double.load(); precondition(observed == 1) }; await check()')
  verify('async-spy-snapshot',
    '@PreviewableDouble protocol ServiceProtocol: Sendable { func load() async -> Int }',
    'let double = ServiceDouble(); double.loadStub = 1; double.loadSpy.pause(); '
    'let operation = Task { await double.load() }; defer { operation.cancel() }; '
    'let call = try await double.loadSpy.waitForCall(); double.loadStub = 2; '
    'call.resume(); let result = await operation.value; precondition(result == 1)')
  verify('async-spy-typed-error',
    'enum Failure: Error { case failed }\n'
    '@PreviewableDouble protocol ServiceProtocol: Sendable { func load() async throws(Failure) -> Int }',
    'let double = ServiceDouble(); double.loadErrorStub = .failed; double.loadSpy.pause(); '
    'let operation = Task { try await double.load() }; '
    'let call = try await double.loadSpy.waitForCall(); operation.cancel(); call.resume(); '
    'do { _ = try await operation.value; fatalError("expected failure") } catch Failure.failed {}')
  for name in ['Result', 'Void', 'Error']:
    verify('async-spy-generic-name-' + name,
      '@PreviewableDouble protocol ServiceProtocol: Sendable { func make<' + name + ': Sendable>(_ type: ' + name + '.Type) async throws -> ' + name + ' }',
      'let double = ServiceDouble(); double.makeStub.set(42, for: Int.self); '
      'let value = try await double.make(Int.self); precondition(value == 42)')
  verify('async-spy-parameter-shadowing',
    '@PreviewableDouble protocol ServiceProtocol: Sendable { func load(response: Int) async -> Int }',
    'let double = ServiceDouble(); double.loadStub = 42; '
    'let value = await double.load(response: 1); precondition(value == 42)')
  verify('async-spy-static',
    '@PreviewableDouble protocol ServiceProtocol: Sendable { static func load() async -> Int }',
    'let result = try await ServiceDouble.withStaticStubs { ServiceDouble.loadStub = 42; '
    'ServiceDouble.loadSpy.pause(); let operation = Task { await ServiceDouble.load() }; '
    'defer { operation.cancel() }; let call = try await ServiceDouble.loadSpy.waitForCall(); '
    'call.resume(); return await operation.value }; precondition(result == 42)')
  verify('async-getter-spy',
    '@PreviewableDouble protocol ServiceProtocol: Sendable { var value: Int { get async throws } }',
    'let double = ServiceDouble(); double.valueStub = 42; double.valueSpy.pause(); '
    'let operation = Task { try await double.value }; defer { operation.cancel() }; '
    'let call = try await double.valueSpy.waitForCall(); call.resume(); '
    'let result = try await operation.value; precondition(result == 42)')
  for first, second in [('get async', 'get'), ('get', 'get async throws'),
      ('get async throws', 'get async'), ('get async throws(FirstFailure)', 'get async throws(SecondFailure)')]:
    verify('async-getter-inheritance-' + first + '-' + second,
      'enum FirstFailure: Error { case failed }\nenum SecondFailure: Error { case failed }\n'
      'protocol First { var value: Int { ' + first + ' } }\n'
      'protocol Second { var value: Int { ' + second + ' } }\n'
      '@PreviewableDouble protocol ServiceProtocol: First, Second {}')
  for actor in ['MainActor', 'Context']:
    verify('async-getter-actor-' + actor,
      '@globalActor actor Context { static let shared = Context() }\nfinal class Payload {}\n'
      '@' + actor + ' @PreviewableDouble protocol ServiceProtocol { var value: Payload? { get async } }')
  verify('async-spy-nonisolated-member',
    '@MainActor @PreviewableDouble protocol ServiceProtocol { nonisolated func load() async -> Int }')
  verify('async-spy-default-main-actor',
    '@PreviewableDouble protocol ServiceProtocol { func load() async -> Int }',
    flags=('-default-isolation', 'MainActor'))
  verify('async-spy-release',
    '@PreviewableDouble protocol ServiceProtocol { var value: Int { get async throws } }', release=True)
  verify('static-instance-same-name',
    '@PreviewableDouble protocol ServiceProtocol { static func load() -> Int; func load() -> Int }',
    'ServiceDouble.withStaticStubs { let double = ServiceDouble(); double.loadStub = 1; '
    'ServiceDouble.loadStub = 2; precondition(double.load() == 1 && ServiceDouble.load() == 2) }')
  verify('subscript-closure-index',
    '@PreviewableDouble protocol ServiceProtocol { subscript(_ predicate: () -> Bool) -> Int { get } }',
    'let double = ServiceDouble(); double.subscriptStub = 42; precondition(double[{ true }] == 42)')
  verify('subscript-setter-index-shadowing',
    '@PreviewableDouble protocol ServiceProtocol { subscript(_ newValue: Int) -> String { get set } }',
    'let double = ServiceDouble(); double.subscriptStub = "ready"; double[42] = "write"; '
    'precondition(double[42] == "ready")')
  verify('subscript-typed-throws',
    'enum Failure: Error { case failed }\n@PreviewableDouble protocol ServiceProtocol { '
    'subscript(_ index: Int) -> Int { get throws(Failure) } }',
    'let double = ServiceDouble(); double.subscriptErrorsStub = [Failure.failed]; '
    'do { let _ = try double[1]; fatalError("expected error") } catch Failure.failed {}')
  verify('overload-readable-name-collision',
    '@PreviewableDouble protocol ServiceProtocol { '
    'func load(_ value: Int) -> Int; func load(_ value: String) -> Int; func loadInt() -> Int }')
  verify('generic-subscript-shadowing',
    'enum Scope { struct Value {}\n@PreviewableDouble protocol ServiceProtocol { '
    'subscript<Value: Sendable>(_ type: Value.Type) -> Value { get } } }',
    'let double = ServiceDouble(); double.subscriptStub.set(42, for: Int.self); precondition(double[Int.self] == 42)')
  verify('associated-constraint-local-alias',
    'enum Scope { typealias Output = String; @PreviewableDouble protocol ServiceProtocol where Value == Output { '
    'associatedtype Value; func load() -> Value } }',
    'let double = ServiceDouble(); double.loadStub = "ready"; precondition(double.load() == "ready")')
  verify('associated-self-qualified-type',
    '@PreviewableDouble protocol ServiceProtocol<Value>: Sendable { '
    'associatedtype Value: Sendable; func load() -> Self.Value }',
    'let double = ServiceDouble<String>(); double.loadStub = "ready"; precondition(double.load() == "ready")')
  verify('inherited-equivalent-actor-isolation',
    '@MainActor protocol Base { func load() -> Int }\n'
    '@PreviewableDouble protocol ServiceProtocol: Base { @MainActor func load() -> Swift.Int }')

  verify('empty-fake-parentheses', '@PreviewableFake() struct Model { let value: Int }',
    'precondition(Model.fake(value: 42).value == 42)')
  verify('empty-class-parentheses', '@PreviewableFake() final class Model { var value = 0 }',
    'precondition(Model.fake(value: 42).value == 42)')
  for storage in ['private var cache = 0', 'private let cache: Int']:
    verify('hidden-storage-' + ('var' if 'var' in storage else 'let'),
      '@PreviewableFake struct Model { ' + storage + '; let name: String; init(name: String) { self.cache = 0; self.name = name } }',
      'precondition(Model.fake(name: "value").name == "value")')
  verify('hidden-class-storage',
    '@PreviewableFake final class Model { private let cache: Int; var value = 0; init() { cache = 1 } }',
    'precondition(Model.fake(value: 42).value == 42)')
  for actor in ['MainActor', 'Context']:
    verify('initializer-actor-' + actor,
      '@globalActor actor Context { static let shared = Context() }\n@PreviewableFake struct Model { let value: Int; @' + actor + ' init(value: Int) { self.value = value } }',
      generation_error='does not support initializer attribute')
  for number, requirement in enumerate(['init() throws', 'init?()', 'init!()', 'init() async throws']):
    verify('parameterless-' + str(number), '@PreviewableDouble protocol Service { ' + requirement + ' }',
      'let value = ServiceDouble()\nprecondition(value.calledMethods.isEmpty)')
  for parameter in ['Swift.Int', 'Count', 'Scope.Count']:
    verify('equivalent-initializer-' + parameter,
      'typealias Count = Swift.Int\nenum Scope { typealias Count = Swift.Int }\n@PreviewableFake struct Model { let value: Int; init(value: ' + parameter + ') { self.value = value } }',
      'precondition(Model.fake(value: 42).value == 42)')
  for access in ['private', 'fileprivate']:
    verify('inaccessible-parent-' + access, access + ' enum Scope { @PreviewableFake struct Model { let value: Int } }',
      generation_error='inside a private or fileprivate type')
  for release in [False, True]:
    verify('effective-fake-access-' + str(release),
      'enum Scope { @PreviewableFake public struct Model { public let value: Int } }', release=release)
    verify('effective-double-access-' + str(release),
      'enum Scope { @PreviewableDouble public protocol Service {} }', release=release)
  verify('qualified-internal-parameter',
    'public enum Scope { @PreviewableFake struct Helper { let value: Int } }\n@PreviewableFake public struct Model { let value: Scope.Helper }',
    generation_error="uses the internal type 'Scope.Helper'")
  verify('qualified-public-parameter',
    'public enum Scope { @PreviewableFake public struct Helper { public let value: Int } }\n@PreviewableFake public struct Model { let value: Scope.Helper }')
  for marker in ['Swift.Sendable', 'Swift.AnyObject']:
    verify('qualified-marker-' + marker, '@PreviewableDouble protocol Service: ' + marker + ' {}',
      'let value = ServiceDouble()\nprecondition(value.calledMethods.isEmpty)')

  verify('scoped-import', 'import struct Foundation.Date\n@PreviewableFake struct Model { let value: Date }')
  verify('conditional-import', '#if canImport(Foundation)\nimport Foundation\n#endif\n@PreviewableFake struct Model { let value: Date }')
  numbers = '\n'.join(f'let value{i}: Int8' for i in range(300))
  verify('numeric-boundaries', '@PreviewableFake struct Model {\n' + numbers + '\n}',
    'let value = Model.fake()\nprecondition(value.value127 > 0 && value.value299 > 0)')
  verify('observers', '@PreviewableFake struct Model { var value: Int { didSet {} } }',
    'precondition(Model.fake(value: 42).value == 42)')
  verify('typed-throws', 'enum Failure: Error { case failed }\n@PreviewableDouble protocol ServiceProtocol: Sendable { func load() throws(Failure) -> Int }',
    'let double = ServiceDouble()\ndouble.loadErrorsStub = [Failure.failed]\ndo { _ = try double.load(); fatalError("expected error") } catch {}')
  verify('rethrows', '@PreviewableDouble protocol ServiceProtocol { func map(_ transform: () throws -> Int) rethrows -> Int }',
    'let value = ServiceDouble().map { 42 }\nprecondition(value == 0)')
  verify('parameter-shadowing', '@PreviewableDouble protocol ServiceProtocol { func load(calledMethods: Int, passedParameters: Int, loadStub: Int, _previewableLock: Int) -> Int }',
    'let double = ServiceDouble()\ndouble.loadStub = 42\nprecondition(double.load(calledMethods: 1, passedParameters: 2, loadStub: 3, _previewableLock: 4) == 42)')
  generic = '@PreviewableDouble protocol ServiceProtocol: Sendable { func load<T: Sendable>(_ type: T.Type) -> T }'
  verify('missing-generic-response', generic, 'let double = ServiceDouble()\nlet _: Int = double.load(Int.self)', crashes=True)
  verify('removed-generic-response', generic,
    'let double = ServiceDouble()\ndouble.loadStub.set(42, for: Int.self)\ndouble.loadStub.remove(for: Int.self)\nlet _: Int = double.load(Int.self)', crashes=True)
  verify('non-sendable-payload', 'final class MutableValue {}\n@PreviewableDouble protocol ServiceProtocol: Sendable { func store(_ value: MutableValue) }',
    compile_error='Sendable')
  verify('main-actor-default', '@PreviewableFake struct Model { let value: Int }\n@PreviewableDouble protocol ServiceProtocol { var count: Int { get set } }',
    flags=('-default-isolation', 'MainActor'))
  verify('custom-global-actor', '@globalActor actor UIContext { static let shared = UIContext() }\nfinal class Payload {}\n@UIContext @PreviewableDouble protocol ServiceProtocol { func store(_ value: Payload) }')
  verify('inherited-global-actor', 'final class Payload {}\nenum Scope { @MainActor protocol Base { func store(_ value: Payload) }\n@PreviewableDouble protocol ServiceProtocol: Base {} }')
  throwing = '@PreviewableFake struct Leaf { let value: Int; init(value: Int) throws { self.value = value } }\n@PreviewableFake struct Model { let leaf: Leaf }'
  verify('nested-throwing', throwing, 'let result = try Model.fake()\nprecondition(result.leaf.value > 0)')
  verify('throwing-closure', '@PreviewableFake struct Leaf { let value: Int; init(value: Int) throws { self.value = value } }\n@PreviewableFake struct Model { let make: () throws -> Leaf }',
    'let model = Model.fake()\nlet value = try model.make()\nprecondition(value.value > 0)')
  verify('throwing-class', '@PreviewableFake final class Model { var value = 0; init() throws {} }',
    'let value = try Model.fake(value: 42)\nprecondition(value.value == 42)')
  verify('release-throwing-signatures', throwing, release=True)
  release_source = '@PreviewableFake struct Model { let value: Int }\n@PreviewableDouble protocol ServiceProtocol { func load() -> Int }'
  output = verify('release-removal', release_source, 'print("release consumer")', release=True)
  symbols = run(['nm', str(output)])
  require_success(symbols, 'release symbols')
  assert 'ServiceDouble' not in symbols.stdout, 'Release executable contains a double implementation'

  domain = root / 'Domain.swift'
  domain.write_text(
    'public struct Token: Sendable { public let value: Int; public init(value: Int) throws { self.value = value } }\n'
    'public struct Kind: Sendable, Equatable { public let name: String; public init(name: String) { self.name = name } }\n'
    'public struct Box<Element> { public let element: Element; public init(element: Element) { self.element = element } }\n'
    'extension Box: Sendable where Element: Sendable {}')
  library = 'libDomain.dylib' if platform.system() == 'Darwin' else 'libDomain.so'
  require_success(run(compiler + ['-emit-module', '-emit-library', '-module-name', 'Domain',
    str(domain), '-o', str(root / library), '-emit-module-path', str(root / 'Domain.swiftmodule'),
    '-module-cache-path', str(root / 'cache')]), 'external module')
  base += ['-I', str(root), '-L', str(root), '-lDomain', '-Xlinker', '-rpath', '-Xlinker', str(root)]
  external = 'import Domain\n@PreviewableFake(parameters: [("value", Int.self)], throwing: true) extension Token {}\n@PreviewableFake struct Model { let token: Token }'
  verify('external-throwing-constructor', external, 'let result = try Model.fake()\nprecondition(result.token.value > 0)')
  verify('external-release-signature', external, release=True)
  verify('inherited-import', ['import struct Domain.Token\nprotocol Base { var token: Token? { get } }',
    '@PreviewableDouble protocol ServiceProtocol: Base {}'])
  synthesizable = ('import Domain\n'
    'extension Kind: @retroactive PreviewableSynthesizable {\n'
    '  public static var previewableDefault: Kind { Kind(name: "synthesized") }\n}\n'
    'extension Box: @retroactive PreviewableSynthesizable where Element: PreviewableSynthesizable {\n'
    '  public static var previewableDefault: Box<Element> { Box(element: Element.previewableDefault) }\n}\n'
    '@PreviewableFake struct Model { let kind: Kind; let box: Box<Int> }\n'
    '@PreviewableDouble protocol ServiceProtocol { var kind: Kind { get }\nfunc load() -> Box<String> }')
  verify('synthesizable-external-default', synthesizable,
    'import Domain\n'
    'let model = Model.fake()\n'
    'precondition(model.kind == Kind(name: "synthesized"))\n'
    'precondition(model.box.element == 0)\n'
    'let double = ServiceDouble()\n'
    'precondition(double.kind == Kind(name: "synthesized"))\n'
    'precondition(double.load().element.isEmpty)\n'
    'precondition(Model.fake(kind: Kind(name: "override")).kind == Kind(name: "override"))')
  verify('synthesizable-release-signature', synthesizable, release=True)
  verify('synthesizable-missing-conformance', 'import Domain\n@PreviewableFake struct Model { let kind: Kind }',
    compile_error='previewableDefault')
