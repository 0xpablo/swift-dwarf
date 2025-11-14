# swift-dwarf

A Swift wrapper for libdwarf, providing type-safe access to DWARF debugging information on macOS and Linux.

[![CI](https://github.com/0xpablo/swift-dwarf/actions/workflows/ci.yml/badge.svg)](https://github.com/0xpablo/swift-dwarf/actions/workflows/ci.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2F0xpablo%2Fswift-dwarf%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/0xpablo/swift-dwarf)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2F0xpablo%2Fswift-dwarf%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/0xpablo/swift-dwarf)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Overview

This library wraps the C libdwarf library to enable Swift programs to read and parse DWARF debugging information from binaries, dSYM bundles, and object files. It's particularly useful for:

- Symbolicating crash addresses to function names and source locations
- Building debugging tools and profilers
- Analyzing binary debug information
- Understanding compiler output and optimization

## Usage

```swift
import DWARF

// Open a binary or dSYM file
let session = try DWARFSession(path: "/path/to/binary")
defer { session.close() }

// Iterate through compilation units
for unit in session.compilationUnits() {
    print("CU Version: \(unit.header.version)")
    // Access DIEs (Debug Information Entries)
    if let child = try unit.die.firstChild() {
        // Process debug info...
    }
}
```

### Extracting Binary UUID

For Mach-O binaries, you can extract the UUID (from LC_UUID load command) to match binaries with their dSYMs:

```swift
let session = try DWARFSession(path: "/path/to/binary.dSYM/Contents/Resources/DWARF/binary")
defer { session.close() }

let info = try session.objectInfo()
if let uuid = info.uuid {
    print("Binary UUID: \(uuid.uuidString)")
    // Use UUID for matching with crash reports, symbol servers, etc.
}
```

### Working with Universal Binaries

For Mach-O universal binaries (containing multiple architectures), you can specify which slice to use:

```swift
// Determine which architecture slice you want
// You can use `lipo -info` or `otool -f` to see available architectures
let options = DWARFSession.Options(architectureIndex: 1) // e.g., arm64 slice
let session = try DWARFSession(path: "/path/to/universal/binary", options: options)
```

### Symbolicating Addresses (With Inline Frames)

```swift
import DWARFSymbolication

let session = try DWARFSession(path: "/path/to/binary")
defer { session.close() }

if let result = try session.symbolicate(address: 0x100000ae0) {
    print("== \(String(format: "%llx", result.address)) ==")
    for frame in result.frames {
        let inlineMarker = frame.isInlined ? "[inlined] " : ""
        print("  \(inlineMarker)\(frame.function) \(frame.file):\(frame.line)")
    }

    if !result.issues.isEmpty {
        print("Symbolication warnings:")
        result.issues.forEach { print("  • \($0)") }
    }
}
```

`result.frames` contains every inline expansion (innermost first, outermost last), so consumers can render complete call stacks without manually traversing DIEs.

To find available architectures in a universal binary:

```bash
# Show architecture indices
otool -f /path/to/binary

# Example output:
# Fat headers
# fat_magic 0xcafebabe
# nfat_arch 2
# architecture 0         <- x86_64 (index 0)
#     cputype 16777223
#     ...
# architecture 1         <- arm64 (index 1)
#     cputype 16777228
#     ...
```

## Building

```bash
# Clone with submodules
git clone --recursive https://github.com/0xpablo/swift-dwarf.git

# Or if already cloned, initialize submodules
git submodule update --init --recursive

# Build
swift build
swift test
```

## Requirements

- Swift 6.2+
- macOS 10.15+ or Linux
- libdwarf is included as a submodule (using fork with patches)

## License

This Swift wrapper is available under the MIT license. See [LICENSE](LICENSE) for details.

The libdwarf library (included as a submodule) is licensed under LGPL 2.1. This means:
- You can use this Swift wrapper in commercial/proprietary applications
- The Swift wrapper code can remain MIT licensed
- Any modifications to libdwarf itself must remain LGPL 2.1
- Users must be able to replace the libdwarf component (satisfied by the submodule structure)

See [NOTICE](NOTICE) for detailed licensing information.

## Contributing

Contributions are welcome! Please ensure tests pass before submitting PRs.

### libdwarf Submodule

This repository uses a forked version of libdwarf with patches applied:
- **Repository**: https://github.com/0xpablo/libdwarf-code
- **Branch**: `swift-dwarf-patches`

The fork contains patches, each in its own branch for upstream contribution:

1. **`fix-commandsizetotal-bug`**: Fixes incorrect calculation of commandsizetotal in Mach-O headers
2. **`increase-max-commands-size`**: Increases MAX_COMMANDS_SIZE to 256KB for modern macOS binaries
3. **`add-macho-uuid-support`**: Adds UUID extraction from LC_UUID for binary/dSYM matching
4. **`fix-integer-precision-warnings`**: Fixes integer precision loss warnings on 64-bit systems

To update the submodule:
```bash
cd libdwarf
git fetch origin
git checkout swift-dwarf-patches
git pull origin swift-dwarf-patches
cd ..
git add libdwarf
git commit -m "Update libdwarf submodule"
```

### TODO: Expand DWARF 5 Test Coverage

The bundled `Tests/Fixtures/TestProgram.dSYM` fixture is built with DWARF 4, so newer features like `.debug_rnglists` (DW_AT_ranges with `DW_FORM_rnglistx`) never execute in the current tests. We should generate an additional DWARF 5 fixture (for example by compiling the fixture program with `swiftc -g -gdwarf-5 ...`) and add focused tests that assert symbolication/range queries succeed when data lives in `.debug_rnglists` instead of `.debug_ranges`.

## References

- [libdwarf Documentation](https://www.prevanders.net/libdwarfdoc/)
- [DWARF Debugging Standard](https://dwarfstd.org/)
- [Example: findfuncbypc.c](https://github.com/davea42/libdwarf-code/blob/main/src/bin/dwarfexample/findfuncbypc.c) - Example of symbolication
