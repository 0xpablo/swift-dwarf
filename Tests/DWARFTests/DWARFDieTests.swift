import CLibdwarf
import Foundation
import Testing
@testable import DWARF

struct DWARFDieTests {
    private func fixtureBinaryPath() -> String? {
        guard let dSYMURL = Bundle.module.url(forResource: "TestProgram", withExtension: "dSYM") else {
            Issue.record("Could not find TestProgram.dSYM test fixture")
            return nil
        }
        return dSYMURL.appendingPathComponent("Contents/Resources/DWARF/TestProgram").path
    }

    @Test
    func decodeCompileUnitAttributes() throws {
        guard let path = fixtureBinaryPath() else { return }

        let session = try DWARFSession(path: path)
        defer { session.close() }

        var iterator = session.compilationUnits().makeIterator()
        var compileUnits: [DWARFDie] = []
        while let unit = iterator.next() {
            compileUnits.append(unit.die)
        }
        if let error = iterator.error {
            throw error
        }
        #expect(!compileUnits.isEmpty, "Fixture should contain compilation units")

        if let firstCU = compileUnits.first {
            let attributes = try firstCU.attributes()
            #expect(!attributes.isEmpty, "Compile unit should expose attributes")
            let name = try firstCU.name()
            #expect(name != nil, "Compile unit should have DW_AT_name")

            let modules = try firstCU.children(matchingTag: UInt16(DW_TAG_module))
            #expect(!modules.isEmpty, "Compile unit should contain module DIEs")
        }

        guard let codeDie = try findCodeDIE(in: compileUnits) else {
            Issue.record("Fixture did not contain a DIE with DW_AT_low_pc")
            return
        }

        let maybeLow = try codeDie.lowPC()
        let maybeHigh = try codeDie.highPC()
        #expect(maybeLow != nil)
        #expect(maybeHigh == nil || maybeHigh! >= maybeLow!, "high_pc must be >= low_pc")

        let ranges = try codeDie.addressRanges()
        if let low = maybeLow, let high = maybeHigh {
            #expect(!ranges.isEmpty)
            if let firstRange = ranges.first {
                #expect(firstRange.lowerBound == low)
                #expect(firstRange.upperBound == high)
            }
        }
    }

    private func findCodeDIE(in compilationUnits: [DWARFDie]) throws -> DWARFDie? {
        for cu in compilationUnits {
            if let match = try depthFirstSearch(startingAt: cu) {
                return match
            }
        }
        return nil
    }

    private func depthFirstSearch(startingAt die: DWARFDie) throws -> DWARFDie? {
        if try die.lowPC() != nil {
            return die
        }
        var iterator = die.children().makeIterator()
        while let child = iterator.next() {
            if let match = try depthFirstSearch(startingAt: child) {
                return match
            }
        }
        if let error = iterator.error {
            throw error
        }
        return nil
    }
}
