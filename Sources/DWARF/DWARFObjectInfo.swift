import CLibdwarf
import Foundation

/// The kind of object file backing a `DWARFSession`.
public enum DWARFFileType: UInt8, Sendable {
    case unknown = 0
    case elf = 1
    case machO = 2
    case pe = 3
    case archive = 4
    case appleUniversal = 5
}

/// CPU architecture types from Mach-O headers.
public enum DWARFArchitecture: Sendable, Equatable, CustomStringConvertible {
    case arm
    case arm64
    case arm64_32
    case x86
    case x86_64
    case powerpc
    case powerpc64
    case unknown(cpuType: UInt64)

    public var description: String {
        switch self {
        case .arm: return "arm"
        case .arm64: return "arm64"
        case .arm64_32: return "arm64_32"
        case .x86: return "x86"
        case .x86_64: return "x86_64"
        case .powerpc: return "powerpc"
        case .powerpc64: return "powerpc64"
        case .unknown(let cpuType): return "unknown(0x\(String(cpuType, radix: 16)))"
        }
    }
}

/// Indicates how libdwarf resolved the DWARF-carrying path.
public enum DWARFPathSource: UInt8, Sendable {
    case unspecified = 0
    case basic = 1
    case dsym = 2
    case debuglink = 3
}

/// Information about the object file containing DWARF debug data.
///
/// Provides metadata about the binary file including its format, architecture,
/// endianness, and UUID (for Mach-O files). This information is useful for
/// matching binaries with their corresponding dSYMs and understanding the
/// target platform.
///
/// ## Example
///
/// ```swift
/// let info = try session.objectInfo()
///
/// // Check file type and architecture
/// print("File type: \(info.fileType)")
/// print("Architecture: \(info.architecture)")
///
/// // For Mach-O files, get the UUID for dSYM matching
/// if let uuid = info.uuid {
///     print("UUID: \(uuid.uuidString)")
/// }
///
/// // Check if this is a universal binary
/// if info.universalBinaryCount > 1 {
///     print("Universal binary with \(info.universalBinaryCount) architectures")
///     print("Currently using index: \(info.universalBinaryIndex)")
/// }
/// ```
///
/// ## Topics
///
/// ### File Information
/// - ``fileType``
/// - ``pathSource``
///
/// ### Architecture Details
/// - ``architecture``
/// - ``pointerSize``
/// - ``isBigEndian``
///
/// ### Binary Identification
/// - ``uuid``
/// - ``machineIdentifier``
///
/// ### Universal Binary Support
/// - ``universalBinaryCount``
/// - ``universalBinaryIndex``
/// - ``universalBinaryOffset``
public struct DWARFObjectInfo: Sendable {
    public let fileType: DWARFFileType
    public let pointerSize: UInt8
    public let isBigEndian: Bool
    public let machineIdentifier: UInt64
    public let objectTypeCode: UInt64
    public let flags: UInt64
    public let pathSource: DWARFPathSource
    public let universalBinaryOffset: UInt64
    public let universalBinaryCount: UInt64
    public let universalBinaryIndex: UInt64
    public let comdatGroupNumber: UInt64

    /// The 128-bit UUID from LC_UUID load command (Mach-O only).
    /// nil if no UUID is present or for non-Mach-O files.
    /// Used for matching binaries with their dSYMs.
    public let uuid: UUID?

    /// The CPU architecture extracted from the machine identifier.
    /// For Mach-O files, this decodes the CPU type to a human-readable architecture.
    public var architecture: DWARFArchitecture {
        // Mach-O CPU type constants
        // See: <mach/machine.h>
        let CPU_ARCH_ABI64: UInt64 = 0x01000000
        let CPU_ARCH_ABI64_32: UInt64 = 0x02000000

        let CPU_TYPE_ARM: UInt64 = 12
        let CPU_TYPE_X86: UInt64 = 7
        let CPU_TYPE_POWERPC: UInt64 = 18

        // Extract base CPU type (without ABI flags)
        let baseCpuType = machineIdentifier & ~(CPU_ARCH_ABI64 | CPU_ARCH_ABI64_32)
        let hasABI64 = (machineIdentifier & CPU_ARCH_ABI64) != 0
        let hasABI64_32 = (machineIdentifier & CPU_ARCH_ABI64_32) != 0

        switch baseCpuType {
        case CPU_TYPE_ARM:
            if hasABI64 && hasABI64_32 {
                return .arm64_32
            } else if hasABI64 {
                return .arm64
            } else {
                return .arm
            }

        case CPU_TYPE_X86:
            if hasABI64 {
                return .x86_64
            } else {
                return .x86
            }

        case CPU_TYPE_POWERPC:
            if hasABI64 {
                return .powerpc64
            } else {
                return .powerpc
            }

        default:
            return .unknown(cpuType: machineIdentifier)
        }
    }
}
