// Simple test program with known functions and line numbers for DWARF testing
import Foundation

// Line 5: Simple function
func greet(name: String) -> String {
    return "Hello, \(name)!"
}

// Line 10: Function with multiple statements
func calculate(a: Int, b: Int) -> Int {
    let sum = a + b
    let product = a * b
    return sum + product
}

// Line 16: Nested function
func outer() {
    func inner(value: Int) -> Int {
        return value * 2
    }
    let result = inner(value: 42)
    print("Result: \(result)")
}

// Line 26: Inline demonstrations
@inline(__always)
func inlineMultiply(_ value: Int, by factor: Int) -> Int {
    return value * factor
}

@inline(__always)
func inlineAdd(_ lhs: Int, _ rhs: Int) -> Int {
    return lhs + rhs
}

@inline(__always)
func inlineChainHelper(_ value: Int) -> Int {
    let doubled = inlineMultiply(value, by: 2)
    return inlineAdd(doubled, 5)
}

@inline(never)
func inlineChain(value: Int) -> Int {
    return inlineChainHelper(value)
}

// Line 47: Main entry point
print(greet(name: "DWARF"))
print(calculate(a: 10, b: 5))
outer()
print("Inline chain: \(inlineChain(value: 7))")
