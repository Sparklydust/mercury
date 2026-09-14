#!/usr/bin/env python3
"""Compile and execute generated consumers in disposable directories."""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--products', type=Path, required=True)
parser.add_argument('--swiftc', default='swiftc')
args = parser.parse_args()
products = args.products.resolve()
generator = products / 'PreviewableGenerator'
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
  base = [args.swiftc, '-swift-version', '6', '-I', str(modules),
    '-module-cache-path', str(root / 'cache'),
    '-load-plugin-executable', f'{plugin}#PreviewableMacrosPlugin']

  def verify(name, source, main='', release=False, compile_error=None, crashes=False, flags=(), generation_error=None):
    folder = root / name
    folder.mkdir()
    originals = []
    for index, text in enumerate([source] if isinstance(source, str) else source):
      original = folder / f'Model{index}.swift'
      original.write_text('import Mercury\n' + text)
      originals.append(str(original))
    generated = folder / 'Generated.swift'
    generation = run([str(generator), str(generated)] + originals)
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
          assert result.returncode != 0 and 'Missing Previewable response' in result.stderr, name + ': ' + result.stderr
        else:
          require_success(result, name + ' execution')
    print('PASS', name, flush=True)
    return output

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
      '@PreviewableDouble protocol ServiceProtocol { func make' + signature + ' }',
      generation_error='requires a Sendable constraint')
  for number, signature in enumerate([
    '<Value: Sendable>() -> Value', '<Value>() -> Value where Value: Swift.Sendable',
    '<Value: Codable & Sendable>() -> [Value]', '<Value: Transferable>() -> Value?',
  ]):
    verify('constrained-generic-response-' + str(number),
      'protocol Transferable: Sendable {}\n@PreviewableDouble protocol ServiceProtocol { func make' + signature + ' }')
  for actor in ['MainActor', 'Context', 'Scope.Context']:
    actor_source = (
      '@globalActor actor Context { static let shared = Context() }\n'
      'enum Scope { @globalActor actor Context { static let shared = Context() } }\n'
      'final class Payload {}\n@PreviewableDouble protocol ServiceProtocol {\n'
      '  @' + actor + ' var payload: Payload? { get set }\n'
      '  @' + actor + ' func store(_ value: Payload) -> Payload?\n'
      '  @' + actor + ' init(value: Payload)\n'
      '  func count() -> Int\n}')
    verify('requirement-actor-' + actor, actor_source)
    verify('requirement-stub-isolation-' + actor, actor_source,
      'nonisolated func configure(_ double: ServiceDouble) { double.payloadStub = Payload() }',
      compile_error='isolated property')
  verify('inherited-requirement-actor',
    'final class Payload {}\nenum Scope {\n'
    '  @globalActor actor Context { static let shared = Context() }\n'
    '  protocol Base { @Context func store(_ value: Payload) }\n'
    '}\n@PreviewableDouble protocol ServiceProtocol: Scope.Base {}')

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
  domain.write_text('public struct Token: Sendable { public let value: Int; public init(value: Int) throws { self.value = value } }')
  require_success(run([args.swiftc, '-swift-version', '6', '-emit-module', '-emit-library', '-module-name', 'Domain',
    str(domain), '-o', str(root / 'libDomain.dylib'), '-emit-module-path', str(root / 'Domain.swiftmodule'),
    '-module-cache-path', str(root / 'cache')]), 'external module')
  base += ['-I', str(root), '-L', str(root), '-lDomain', '-Xlinker', '-rpath', '-Xlinker', str(root)]
  external = 'import Domain\n@PreviewableFake(parameters: [("value", Int.self)], throwing: true) extension Token {}\n@PreviewableFake struct Model { let token: Token }'
  verify('external-throwing-constructor', external, 'let result = try Model.fake()\nprecondition(result.token.value > 0)')
  verify('external-release-signature', external, release=True)
  verify('inherited-import', ['import struct Domain.Token\nprotocol Base { var token: Token? { get } }',
    '@PreviewableDouble protocol ServiceProtocol: Base {}'])
