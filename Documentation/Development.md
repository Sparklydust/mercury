# Development

Run `swift test` locally. macOS CI also verifies bundled tools and generated consumers, runs tests with Thread Sanitizer, and builds Release. Linux CI tests source-built tools, generated consumers, and Release compilation.

### Updating bundled tools

Mercury bundles the generator and macro plugin to avoid compiling them and SwiftSyntax in consumer builds. Consumers do not need to rebuild these binaries.

Rebuild after changing generator, generator core, macro implementation or launcher sources, `Package.swift`, `Package.resolved`, or `Scripts/generator-artifact.py`. README and test-only edits do not require rebuilding. Source fingerprints include comments and file headers. Finish source edits and formatting before rebuilding.

From the repository root, using an Apple Silicon Mac with Xcode 27 / Swift 6.4 and Python 3:

```sh
python3 Scripts/generator-artifact.py build --version 1.0.0
```

Use the intended release version. The command builds both tools for Apple Silicon, packages and signs them, updates checksums and the macro revision, and verifies the result. Include the following with the source changes:

- `Artifacts/PreviewableGenerator.artifactbundle/` (executables, metadata, and SwiftSyntax license).
- `Sources/PreviewableMacrosLauncher/BundledMacroRevision.swift`.

Verify the final files before committing:

```sh
python3 Scripts/generator-artifact.py verify
```

Verification checks source fingerprints, checksums, architectures, and signatures. CI rejects a stale bundle. For source development, run `MERCURY_BUILD_GENERATOR_FROM_SOURCE=1 swift test` before rebuilding the bundle.
