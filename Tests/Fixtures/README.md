# Test Fixtures

This directory contains test binaries with DWARF debug information for testing the swift-dwarf library.

## TestProgram

A simple Swift program compiled with debug symbols for testing DWARF parsing.

### Files

- `TestProgram.swift` - Source code (checked into git)
- `TestProgram.dSYM/` - dSYM bundle with DWARF debug info (checked into git)
- `TestProgram` - Compiled binary (NOT checked into git, regenerate with build script)

### Regenerating the Fixture

```bash
cd Tests/Fixtures
swiftc -g -Onone TestProgram.swift -o TestProgram
```

This will create both `TestProgram` (stripped binary) and `TestProgram.dSYM` (debug symbols).

### Known Debug Information

The test program contains these functions at known line numbers:

- Line 5: `greet(name:)` - Simple string function
- Line 10: `calculate(a:b:)` - Math function with multiple statements
- Line 16: `outer()` - Function with nested closure
- Line 17: `inner(value:)` - Nested function inside `outer()`
- Line 26-34: Inline helper functions (`inlineMultiply`, `inlineAdd`)
- Line 37: `inlineChainHelper(_:)` - Inlined into `inlineChain`
- Line 43: `inlineChain(value:)` - Calls the inline helpers
- Line 47-51: Top-level code

This makes it easy to write tests that verify specific addresses map to expected functions/lines.
