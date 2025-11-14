import DWARF

/// Symbolication metadata for a single address.
///
/// The ``frames`` array exposes the full inline-aware call stack (innermost first), while
/// ``issues`` captures any non-fatal problems encountered while reading DWARF data.
public struct DWARFSymbolicationResult {
    public let address: UInt64
    public let functionName: String?
    public let file: String?
    public let line: UInt64?
    public let column: UInt64?
    public let die: DWARFDie?
    public let compilationUnit: DWARFCompilationUnit
    /// Inline-aware call stack frames, ordered from innermost (index 0) to outermost.
    public let frames: [DWARFInlineFrame]
    public let issues: [DWARFSymbolicationIssue]
}

extension DWARFSession {
    /// Symbolicates `address`, returning file/line information and its inline-aware call stack.
    ///
    /// - Parameters:
    ///   - address: Runtime address to symbolize (for example from a crash report).
    ///   - section: DWARF section to search; `.info` by default.
    ///   - options: Controls how libdwarf errors are surfaced via ``SymbolicationOptions``.
    /// - Returns: A ``DWARFSymbolicationResult`` if debug info exists for `address`, otherwise `nil`.
    /// - Throws: ``DWARFError`` when libdwarf reports a fatal failure and the error policy is `.strict`.
    public func symbolicate(
        address: UInt64,
        section: DWARFSection = .info,
        options: SymbolicationOptions = SymbolicationOptions()
    ) throws -> DWARFSymbolicationResult? {
        guard let unit = try compilationUnit(containing: address, section: section) else {
            return nil
        }

        let lineTable = try unit.lineTable()
        let symbolicated = try unit.symbolicateAddress(address, options: options)
        let frames = symbolicated?.frames ?? []
        let issues = symbolicated?.issues ?? []
        let primaryFrame = frames.first
        let die = try unit.subprogram(at: address)
        let fallbackLocation = lineTable?.location(for: address)

        let resolvedFile: String?
        if let frameFile = primaryFrame?.file, !frameFile.isEmpty {
            resolvedFile = frameFile
        } else {
            resolvedFile = fallbackLocation?.file
        }

        func resolvedLine(_ value: UInt64?) -> UInt64? {
            guard let value else { return fallbackLocation?.line }
            if value == 0 { return fallbackLocation?.line }
            return value
        }

        func resolvedColumn(_ value: UInt64?) -> UInt64? {
            guard let value else { return fallbackLocation?.column }
            if value == 0 { return fallbackLocation?.column }
            return value
        }

        let functionName = frames.last?.function ?? die?.symbolicatedDisplayName()
        return DWARFSymbolicationResult(
            address: address,
            functionName: functionName,
            file: resolvedFile,
            line: resolvedLine(primaryFrame?.line),
            column: resolvedColumn(primaryFrame?.column),
            die: die,
            compilationUnit: unit,
            frames: frames,
            issues: issues
        )
    }
}
