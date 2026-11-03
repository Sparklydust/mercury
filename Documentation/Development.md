# Development

Run `swift test` locally. macOS CI also verifies bundled tools and generated consumers, runs tests with Thread Sanitizer, and builds Release. Linux CI tests source-built tools, generated consumers, and Release compilation.

Commit `Package.resolved` and the bundled tools together when dependencies change. Environment examples may be committed; local environment files, build output, and Vapor's `db.sqlite` runtime files are ignored.

Keep each extension in its own Swift file under the owning target's `Extensions` directory. Group files by extended type when that type has several extension files. Keep protocol declarations separate from their conformances.

### Async spy changes

Keep the spy runtime tests under `Cases/Mercury/Features/PreviewableDouble` and generated consumer tests under `Cases/PreviewableBuildToolPlugin`. Cover actor isolation, typed errors, per-invocation snapshots, cancellation, and bounded waits. Coordinate tests through call handles rather than sleeps.

Run `MERCURY_BUILD_GENERATOR_FROM_SOURCE=1 swift test` while editing generation. The test target selects the matching macro implementation explicitly, so switching between source-built and bundled tools does not select stale modules from the build cache.

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

### Preparing a public release

Review changes to the public macros, runtime types, and generated member names for source compatibility. Keep the README's versioned installation example, supported toolchains, and usage limitations consistent with the release.

Verify the bundle, run `swift test` with the default bundled tools, and run `Scripts/verify-generated.py` against the package's Debug products. macOS CI must also pass Thread Sanitizer and Release compilation; Linux CI must pass tests, generated consumers, and Release compilation.

The consumer verification script compiles for macOS 15, matching the package's minimum deployment target. Keep this target aligned with `Package.swift` when changing platform support. Building still requires Xcode 27 / Swift 6.4.

Confirm that a separate Swift package can use the library and plugin in Debug and compile its production code in Release. The release tag must contain the reviewed source, matching bundled tools, and documentation. Publishing a tag or GitHub release is a separate action after these checks pass.
