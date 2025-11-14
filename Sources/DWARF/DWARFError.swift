import CLibdwarf

/// Represents an error reported by libdwarf.
public struct DWARFError: Error, CustomStringConvertible {
    /// Numeric identifier returned by libdwarf.
    public let code: UInt64
    /// Human readable description.
    public let message: String

    public var description: String { "libdwarf error \(code): \(message)" }
}

extension DWARFError {
    /// Creates a Swift error from the libdwarf error pointer and frees the underlying C allocation.
    /// - Parameters:
    ///   - debug: DWARF handle associated with the error (if any).
    ///   - error: Pointer returned by libdwarf.
    /// - Returns: A Swift representation of the error.
    static func consume(debug: Dwarf_Debug?, error: Dwarf_Error?) -> DWARFError {
        guard let error else {
            return DWARFError(code: 0, message: "Unknown libdwarf error.")
        }
        let numericCode = UInt64(dwarf_errno(error))
        let message: String
        if let cMessage = dwarf_errmsg(error) {
            message = String(cString: cMessage)
        } else {
            message = "Unknown libdwarf error."
        }
        dwarf_dealloc_error(debug, error)
        return DWARFError(code: numericCode, message: message)
    }
}
