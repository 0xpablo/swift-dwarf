import Foundation
import Testing
import DWARF
@testable import DWARFSymbolication

struct DWARFSymbolicationTests {
    private func fixtureBinaryPath() -> String? {
        guard let dSYMURL = Bundle.module.url(forResource: "TestProgram", withExtension: "dSYM") else {
            Issue.record("Could not find TestProgram.dSYM test fixture")
            return nil
        }
        return dSYMURL.appendingPathComponent("Contents/Resources/DWARF/TestProgram").path
    }

    @Test
    func resolvesFunctionNameAndLocation() throws {
        guard let path = fixtureBinaryPath() else { return }
        let session = try DWARFSession(path: path)
        defer { session.close() }

        // Address for greet(name:) gleaned from dwarfdump/atos
        let greetAddress: UInt64 = 0x0000000100000ae0
        guard let result = try session.symbolicate(address: greetAddress) else {
            Issue.record("Failed to symbolicate greet()")
            return
        }

        #expect(result.functionName == "TestProgram.greet(name: Swift.String) -> Swift.String")
        #expect(result.file?.hasSuffix("TestProgram.swift") == true)
        #expect(result.line == 5)
        #expect(result.frames.count >= 1)
        let frame = result.frames.first!
        #expect(frame.function.contains("greet"))
        #expect(frame.file.hasSuffix("TestProgram.swift"))
        #expect(frame.line == 5)
        #expect(result.issues.isEmpty)
    }

    @Test
    func symbolicateInlineAddressIncludesFrames() throws {
        guard let path = fixtureBinaryPath() else { return }
        let session = try DWARFSession(path: path)
        defer { session.close() }

        // Address inside calculate(_:b:) that records inline runtime overflow checks.
        let inlineAddress: UInt64 = 0x0000000100000d1e

        guard let result = try session.symbolicate(address: inlineAddress) else {
            Issue.record("Failed to symbolicate inline-heavy address via session API")
            return
        }

        #expect(result.frames.count >= 2)
        let inlineFrame = result.frames.first!
        #expect(inlineFrame.isInlined)
        #expect(inlineFrame.file.hasSuffix("TestProgram.swift"))
        #expect(inlineFrame.line == 11)
        #expect(inlineFrame.column == 17)

        let outerFrame = result.frames.last!
        #expect(outerFrame.isInlined == false)
        #expect(outerFrame.function.contains("calculate"))
        #expect(result.file == inlineFrame.file)
        #expect(result.line == inlineFrame.line)
        #expect(result.column == inlineFrame.column)
    }
}
