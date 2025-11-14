import Foundation
import Testing
@testable import DWARF

struct DWARFObjectInfoTests {
    @Test
    func objectInfoMatchesFixtureMetadata() throws {
        guard let dSYMURL = Bundle.module.url(forResource: "TestProgram", withExtension: "dSYM") else {
            Issue.record("Could not find TestProgram.dSYM test fixture")
            return
        }
        let dwarfBinaryPath = dSYMURL.path + "/Contents/Resources/DWARF/TestProgram"

        let session = try DWARFSession(path: dwarfBinaryPath)
        defer { session.close() }

        let info = try session.objectInfo()
        #expect(info.fileType == .machO || info.fileType == .appleUniversal)
        #expect(info.pointerSize == 4 || info.pointerSize == 8)
        #expect(info.universalBinaryCount >= info.universalBinaryIndex)
        #expect(info.pathSource == .basic || info.pathSource == .dsym)

        // Verify architecture detection
        let arch = info.architecture
        #expect(arch == .arm64 || arch == .x86_64 || arch == .arm || arch == .x86,
                "Expected a known architecture, got: \(arch)")

        // Verify it matches the pointer size
        switch arch {
        case .arm64, .x86_64, .powerpc64:
            #expect(info.pointerSize == 8, "64-bit architecture should have 8-byte pointers")
        case .arm, .x86, .powerpc, .arm64_32:
            #expect(info.pointerSize == 4, "32-bit architecture should have 4-byte pointers")
        case .unknown:
            break // Unknown architectures may have any pointer size
        }

        // Verify UUID extraction matches the actual fixture UUID
        // Verified with: dwarfdump --uuid TestProgram.dSYM/Contents/Resources/DWARF/TestProgram
        let expectedUUID = UUID(uuidString: "09D134C5-0191-4AF4-9E19-7CA87AB0181C")!
        #expect(info.uuid != nil, "Mach-O file should have a UUID")
        if let uuid = info.uuid {
            #expect(uuid == expectedUUID,
                    "UUID should match the fixture's actual UUID")
        }
    }
}
