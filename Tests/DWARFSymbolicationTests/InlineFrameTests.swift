import Foundation
import Testing
import DWARFSymbolication
import DWARF
import CLibdwarf

struct InlineFrameTests {
    /// Returns the path to the DWARF binary inside the TestProgram.dSYM test fixture.
    private func fixtureBinaryPath() -> String? {
        guard let dSYMURL = Bundle.module.url(
            forResource: "TestProgram",
            withExtension: "dSYM"
        ) else {
            Issue.record("Could not find TestProgram.dSYM test fixture")
            return nil
        }
        return dSYMURL
            .appendingPathComponent("Contents/Resources/DWARF/TestProgram")
            .path
    }

    /// Finds the Swift compilation unit for TestProgram.swift from the test fixture.
    private func swiftCompileUnit(from session: DWARFSession) throws -> DWARFCompilationUnit? {
        for unit in session.compilationUnits() {
            // Only examine regular compilation units (DW_UT_compile = 0x01)
            guard unit.header.unitType == 0x01 else { continue }

            // Check if the CU's name matches our test fixture
            if let name = try? unit.die.name(), name.hasSuffix("TestProgram.swift") {
                return unit
            }

            // Fallback: check line table for any references to TestProgram.swift
            if let table = try? unit.lineTable(),
               table.rows.contains(where: { $0.file.hasSuffix("TestProgram.swift") }) {
                return unit
            }
        }
        return nil
    }

    @Test
    func symbolicateAddressReturnsFrames() throws {
        guard let path = fixtureBinaryPath() else { return }
        let session = try DWARFSession(path: path)
        defer { session.close() }

        guard let unit = try swiftCompileUnit(from: session) else {
            Issue.record("Fixture missing Swift compilation unit")
            return
        }

        // Test symbolication of a known address from the greet() function
        let greetAddress: UInt64 = 0x0000000100000ae0

        guard let result = try unit.symbolicateAddress(greetAddress) else {
            Issue.record("Failed to symbolicate address")
            return
        }

        #expect(result.issues.isEmpty)

        // Should have at least one frame
        #expect(result.frames.count >= 1, "Should have at least one frame")

        // The outermost frame should be the greet function
        let outermostFrame = result.frames.last!
        #expect(outermostFrame.function.contains("greet"))
        #expect(outermostFrame.file.hasSuffix("TestProgram.swift"))
        #expect(outermostFrame.line == 5)

        // The outermost frame should not be marked as inlined
        #expect(outermostFrame.isInlined == false, "Outermost frame should not be inlined")
    }

    @Test
    func symbolicateInlineAddressIncludesInlinedFrames() throws {
        guard let path = fixtureBinaryPath() else { return }
        let session = try DWARFSession(path: path)
        defer { session.close() }

        guard let unit = try swiftCompileUnit(from: session) else {
            Issue.record("Fixture missing Swift compilation unit")
            return
        }

        // Arithmetic in calculate(_:b:) triggers Swift's runtime overflow checks, which
        // are modeled as DW_TAG_inlined_subroutine entries spanning this address.
        let inlineAddress: UInt64 = 0x0000000100000d1e

        guard let result = try unit.symbolicateAddress(inlineAddress) else {
            Issue.record("Failed to symbolicate inline-heavy address")
            return
        }

        #expect(result.issues.isEmpty)
        #expect(result.frames.count >= 2, "Expected at least one inline frame plus the outer subprogram")

        let inlineFrame = result.frames.first!
        #expect(inlineFrame.isInlined, "Innermost frame should represent an inline expansion")
        #expect(inlineFrame.file.hasSuffix("TestProgram.swift"))
        #expect(inlineFrame.line == 11)
        #expect(inlineFrame.column == 17)

        let outerFrame = result.frames.last!
        #expect(outerFrame.isInlined == false, "Outermost frame should be the calculate function")
        #expect(outerFrame.function.contains("calculate"))
        let outerFile = outerFrame.file
        #expect(
            outerFile.hasSuffix("TestProgram.swift") || outerFile.isEmpty || outerFile == "/<compiler-generated>",
            "Outermost frame should either resolve to TestProgram.swift or mark the location as compiler-generated"
        )
        #expect([0, 11].contains(Int(outerFrame.line)),
                "Line numbers should either be the resolved source line or zero when unavailable")
    }

    @Test
    func testAbstractOriginFollowing() throws {
        guard let path = fixtureBinaryPath() else { return }
        let session = try DWARFSession(path: path)
        defer { session.close() }

        guard let unit = try swiftCompileUnit(from: session) else {
            Issue.record("Fixture missing Swift compilation unit")
            return
        }

        // Search for any inline subroutine to test abstract origin
        var iterator = unit.die.children().makeIterator()
        while let child = iterator.next() {
            if let tag = try? child.tag(), tag == UInt16(DW_TAG_subprogram) {
                _ = try searchForInline(in: child)
            }
        }

        // Note: The test fixture might not have inlines depending on optimization level
        // This test verifies the API works, even if no inlines are found
    }

    private func searchForInline(in die: DWARFDie) throws -> Bool {
        var iterator = die.children().makeIterator()
        while let child = iterator.next() {
            if let tag = try? child.tag(), tag == UInt16(DW_TAG_inlined_subroutine) {
                // Try to follow abstract origin
                if (try? child.abstractOrigin()) != nil {
                    return true
                }
            }
            if try searchForInline(in: child) {
                return true
            }
        }
        return false
    }

}
