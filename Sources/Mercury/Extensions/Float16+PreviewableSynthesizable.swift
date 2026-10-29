//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

#if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
extension Float16: PreviewableSynthesizable {}
#endif
