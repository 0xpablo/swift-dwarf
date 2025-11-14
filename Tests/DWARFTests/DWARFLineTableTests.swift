import Foundation
import Testing
@testable import DWARF

struct DWARFLineTableTests {
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

    @Test
    func loadLineTableFromFirstCompilationUnit() throws {
        guard let path = fixtureBinaryPath() else { return }
        let session = try DWARFSession(path: path)
        defer { session.close() }

        guard let unit = try swiftCompileUnit(from: session) else {
            Issue.record("Fixture did not contain Swift compilation unit")
            return
        }

        let table = try unit.lineTable()
        #expect(table != nil, "Compilation unit should have a line table")

        // Verify the line table contains meaningful data
        let hasValidRows = table?.rows.contains { $0.line > 0 } ?? false
        #expect(hasValidRows, "Line table should contain rows with line numbers")
    }

    @Test
    func lookupLocationByAddress() throws {
        guard let path = fixtureBinaryPath() else { return }
        let session = try DWARFSession(path: path)
        defer { session.close() }

        guard let unit = try swiftCompileUnit(from: session) else {
            Issue.record("Fixture missing Swift compilation unit")
            return
        }

        guard let table = try unit.lineTable() else {
            Issue.record("Compilation unit missing line table")
            return
        }

        // Test symbolication of a known address from the greet() function
        // Address verified with: atos -o Tests/Fixtures/TestProgram.dSYM/Contents/Resources/DWARF/TestProgram 0x100000ae0
        let greetAddress: UInt64 = 0x0000000100000ae0

        // Verify line number lookup
        guard let location = table.location(for: greetAddress) else {
            Issue.record("Failed to map address to source location")
            return
        }
        #expect(location.file.hasSuffix("TestProgram.swift"))
        #expect(location.line == 5)

        // Verify function name lookup (should be demangled with full signature)
        // Note: Swift's swift_demangle only supports flags=0 which returns fully qualified names.
        // atos does additional post-processing to simplify (remove module/types).
        let functionName = try unit.functionName(at: greetAddress)
        #expect(functionName?.contains("greet") == true)
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
    func respectsMultipleLineSequences() {
        let rows: [DWARFLineTable.Row] = [
            .init(
                address: 0x0000000000001000,
                file: "seq1.swift",
                fileIndex: nil,
                line: 10,
                column: 0,
                isStatement: true,
                isEndSequence: false,
                isActual: false
            ),
            .init(
                address: 0x0000000000001010,
                file: "seq1.swift",
                fileIndex: nil,
                line: 11,
                column: 0,
                isStatement: true,
                isEndSequence: true,
                isActual: false
            ),
            .init(
                address: 0x0000000000000200,
                file: "seq2.swift",
                fileIndex: nil,
                line: 20,
                column: 0,
                isStatement: true,
                isEndSequence: false,
                isActual: false
            ),
            .init(
                address: 0x0000000000000210,
                file: "seq2.swift",
                fileIndex: nil,
                line: 21,
                column: 0,
                isStatement: true,
                isEndSequence: true,
                isActual: false
            )
        ]

        let table = DWARFLineTable(version: 5, rows: rows)

        let seq1Location = table.row(containing: 0x0000000000001005)
        #expect(seq1Location?.address == 0x0000000000001000)
        #expect(seq1Location?.file == "seq1.swift")

        let seq2Location = table.row(containing: 0x0000000000000208)
        #expect(seq2Location?.address == 0x0000000000000200)
        #expect(seq2Location?.file == "seq2.swift")

        // Address outside any recorded sequence should return nil instead of borrowing data
        #expect(table.row(containing: 0x0000000000000300) == nil)
    }

    @Test
    func filePathLookupReturnsRecordedEntry() {
        let table = DWARFLineTable(
            version: 5,
            rows: [],
            filePaths: [2: "/tmp/Example.swift"]
        )

        #expect(table.filePath(forFileIndex: 2) == "/tmp/Example.swift")
        #expect(table.filePath(forFileIndex: 1) == nil)
    }
}
