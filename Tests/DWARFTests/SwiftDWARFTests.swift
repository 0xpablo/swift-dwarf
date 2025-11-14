import Foundation
import Testing
@testable import DWARF

struct DWARFSessionTests {
    @Test
    func openingInvalidFileProducesDwarfError() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try "not an object file".write(
            to: tempURL,
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try DWARFSession(path: tempURL.path)
            #expect(Bool(false), "Expected libdwarf to reject a non-object file.")
        } catch let error as DWARFError {
            #expect(!error.message.isEmpty)
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test
    func enumeratesCompilationUnitsFromTestFixture() throws {
        guard let dSYMURL = Bundle.module.url(forResource: "TestProgram", withExtension: "dSYM") else {
            Issue.record("Could not find TestProgram.dSYM test fixture")
            return
        }

        let dwarfBinaryPath = dSYMURL.path + "/Contents/Resources/DWARF/TestProgram"

        let session = try DWARFSession(path: dwarfBinaryPath)
        defer { session.close() }

        var iterator = session.compilationUnits().makeIterator()
        var unitCount = 0
        var foundTestProgram = false

        while let unit = iterator.next() {
            unitCount += 1

            // Verify basic unit properties
            #expect(unit.header.version >= 4) // DWARF version 4 or 5
            #expect(unit.header.section == .info)

            // Try to get the DIE
            if (try? unit.die.firstChild()) != nil {
                // We found debug info
                foundTestProgram = true
            }

            // Just check first few units
            if unitCount >= 5 {
                break
            }
        }
        if let error = iterator.error {
            throw error
        }

        #expect(unitCount > 0, "Should find at least one compilation unit")
        #expect(foundTestProgram, "Should find debug info for TestProgram")
    }
}
