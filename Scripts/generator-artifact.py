#!/usr/bin/env python3
"""Build or verify Mercury's bundled Apple Silicon generator and compiler plugin."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / 'Artifacts/PreviewableGenerator.artifactbundle'
EXECUTABLE = Path('bin/PreviewableGenerator')
MACROS = Path('bin/PreviewableMacrosPlugin')
REVISION = ROOT / 'Sources/PreviewableMacrosLauncher/BundledMacroRevision.swift'


def digest(path):
  return hashlib.sha256(path.read_bytes()).hexdigest()


def source_digest():
  paths = [ROOT / name for name in ['Package.swift', 'Package.resolved', 'Scripts/generator-artifact.py']]
  for name in ['PreviewableGenerator', 'PreviewableGeneratorCore', 'PreviewableMacrosPlugin', 'PreviewableMacrosLauncher']:
    paths.extend(path for path in (ROOT / 'Sources' / name).rglob('*.swift') if path != REVISION)
  contents = {str(path.relative_to(ROOT)): digest(path) for path in sorted(paths)}
  return hashlib.sha256(json.dumps(contents, sort_keys=True).encode()).hexdigest()


def write_json(path, value):
  path.write_text(json.dumps(value, indent=2) + '\n')


def verify_architectures(executable):
  architectures = subprocess.check_output(['lipo', str(executable), '-archs'], text=True).split()
  if architectures != ['arm64']:
    raise SystemExit(f'Expected an Apple Silicon executable; found {architectures}')


def revision_source(checksum):
  return ('//\n// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.\n//\n\n'
    '/// Identifies the bundled macro implementation and invalidates consumers when it changes.\n'
    f'let bundledMacroRevision = "{checksum}"\n')


def verify():
  metadata = json.loads((BUNDLE / 'build.json').read_text())
  if metadata['sourceSHA256'] != source_digest():
    raise SystemExit('Generator sources changed. Run python3 Scripts/generator-artifact.py build.')
  for name, expected in metadata['files'].items():
    if digest(BUNDLE / name) != expected:
      raise SystemExit(f'Bundled generator checksum mismatch: {name}')
  if REVISION.read_text() != revision_source(metadata['files'][str(MACROS)]):
    raise SystemExit('Bundled macro revision does not match the executable. Rebuild the artifact.')
  for executable in [EXECUTABLE, MACROS]:
    verify_architectures(BUNDLE / executable)
    subprocess.run(['codesign', '--verify', str(BUNDLE / executable)], check=True)
  print('PASS bundled tools source fingerprint, checksums, architectures and signatures', flush=True)


def build(scratch, version):
  environment = dict(os.environ, MERCURY_BUILD_GENERATOR_FROM_SOURCE='1', MERCURY_BUILD_TOOL_ARTIFACTS='1')
  command = ['swift', 'build', '--package-path', str(ROOT), '--scratch-path', str(scratch),
    '--force-resolved-versions', '-c', 'release', '--arch', 'arm64']
  fingerprint = source_digest()
  subprocess.run(command + ['--product', 'PreviewableGenerator'], env=environment, check=True)
  subprocess.run(command + ['--product', 'PreviewableMacrosPlugin'], env=environment, check=True)
  products = Path(subprocess.check_output(command + ['--show-bin-path'], env=environment, text=True).strip())
  with tempfile.TemporaryDirectory(prefix='.mercury-artifact-', dir=BUNDLE.parent) as directory:
    staging = Path(directory)
    (staging / 'bin').mkdir()
    for relative in [EXECUTABLE, MACROS]:
      executable = staging / relative
      shutil.copy2(products / relative.name, executable)
      subprocess.run(['strip', '-S', str(executable)], check=True)
      subprocess.run(['codesign', '--force', '--sign', '-', str(executable)], check=True)
      verify_architectures(executable)
    license_path = Path('licenses/SwiftSyntax-LICENSE.txt')
    (staging / license_path).parent.mkdir()
    shutil.copyfile(scratch / 'checkouts/swift-syntax/LICENSE.txt', staging / license_path)
    write_json(staging / 'info.json', {
      'schemaVersion': '1.0',
      'artifacts': {'PreviewableGenerator': {
        'version': version, 'type': 'executable',
        'variants': [{'path': str(EXECUTABLE),
          'supportedTriples': ['arm64-apple-macosx']}]
      }}
    })
    if fingerprint != source_digest():
      raise SystemExit('Generator sources changed during the build. Run the build again.')
    write_json(staging / 'build.json', {
      'sourceSHA256': fingerprint,
      'swiftVersion': subprocess.check_output(['swift', '--version'], text=True).strip(),
      'files': {str(path): digest(staging / path) for path in [EXECUTABLE, MACROS, Path('info.json'), license_path]}
    })
    if (BUNDLE / license_path).exists():
      (BUNDLE / license_path).chmod(0o644)
    # Replace signed executables atomically so macOS does not reuse the old file's cached signature.
    (BUNDLE / 'bin').mkdir(parents=True, exist_ok=True)
    for relative in [EXECUTABLE, MACROS]:
      (staging / relative).replace(BUNDLE / relative)
    shutil.copytree(staging, BUNDLE, dirs_exist_ok=True)
    REVISION.write_text(revision_source(digest(BUNDLE / MACROS)))
  verify()


if __name__ == '__main__':
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('action', choices=['build', 'verify'])
  parser.add_argument('--scratch-path', type=Path, default=ROOT / '.build/generator-artifact')
  parser.add_argument('--version', default='1.0.0')
  args = parser.parse_args()
  if args.action == 'build':
    build(args.scratch_path.resolve(), args.version)
  else:
    verify()
