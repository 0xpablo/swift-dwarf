import CLibdwarf
import DWARF

extension DWARFCompilationUnit {
    /// Returns the full call stack (including inlined frames) for the specified address.
    /// The frames are ordered from innermost (most specific) to outermost.
    /// Returns nil if no code is found at this address.
    public func symbolicateAddress(
        _ address: UInt64,
        options: SymbolicationOptions = SymbolicationOptions()
    ) throws -> DWARFSymbolicatedAddress? {
        guard let subprogram = try subprogram(at: address) else {
            return nil
        }

        let lineTable = try lineTable()
        var frames: [DWARFInlineFrame] = []
        var issues: [DWARFSymbolicationIssue] = []

        try collectInlineFrames(
            in: subprogram,
            at: address,
            frames: &frames,
            lineTable: lineTable,
            options: options,
            issues: &issues
        )

        if let outermostFrame = try createFrame(
            from: subprogram,
            at: address,
            isInlined: false,
            lineTable: lineTable,
            options: options,
            issues: &issues
        ) {
            frames.append(outermostFrame)
        }

        guard !frames.isEmpty else {
            return nil
        }

        return DWARFSymbolicatedAddress(address: address, frames: frames, issues: issues)
    }

    private func collectInlineFrames(
        in die: DWARFDie,
        at address: UInt64,
        frames: inout [DWARFInlineFrame],
        lineTable: DWARFLineTable?,
        options: SymbolicationOptions,
        issues: inout [DWARFSymbolicationIssue]
    ) throws {
        var iterator = die.children().makeIterator()
        while let child = iterator.next() {
            do {
                let tag = try child.tag()

                if tag == UInt16(DW_TAG_inlined_subroutine) {
                    let containsAddress = try dieContains(child, address: address)
                    if containsAddress {
                        try collectInlineFrames(
                            in: child,
                            at: address,
                            frames: &frames,
                            lineTable: lineTable,
                            options: options,
                            issues: &issues
                        )

                        if let frame = try createFrame(
                            from: child,
                            at: address,
                            isInlined: true,
                            lineTable: lineTable,
                            options: options,
                            issues: &issues
                        ) {
                            frames.append(frame)
                        }
                    }
                } else {
                    try collectInlineFrames(
                        in: child,
                        at: address,
                        frames: &frames,
                        lineTable: lineTable,
                        options: options,
                        issues: &issues
                    )
                }
            } catch {
                try handleSymbolicationError(
                    error,
                    context: "Traversing inline frames",
                    address: address,
                    options: options,
                    issues: &issues
                )
            }
        }

        if let error = iterator.error {
            try handleSymbolicationError(
                error,
                context: "Iterating inline children",
                address: address,
                options: options,
                issues: &issues
            )
        }
    }

    private func createFrame(
        from die: DWARFDie,
        at address: UInt64,
        isInlined: Bool,
        lineTable: DWARFLineTable?,
        options: SymbolicationOptions,
        issues: inout [DWARFSymbolicationIssue]
    ) throws -> DWARFInlineFrame? {
        var nameSource = die
        if isInlined, let origin = (try? die.abstractOrigin()) ?? nil {
            nameSource = origin
        }
        let functionName = nameSource.symbolicatedDisplayName()

        if let lineTable {
            if isInlined {
                do {
                    if let callSite = try inlineCallSite(for: die, lineTable: lineTable) {
                        return DWARFInlineFrame(
                            function: functionName,
                            file: callSite.file,
                            line: callSite.line,
                            column: callSite.column,
                            isInlined: true
                        )
                    }
                } catch {
                    try handleSymbolicationError(
                        error,
                        context: "Reading inline call site",
                        address: address,
                        options: options,
                        issues: &issues
                    )
                }
            }

            if let location = lineTable.location(for: address) {
                return DWARFInlineFrame(
                    function: functionName,
                    file: location.file,
                    line: location.line,
                    column: location.column,
                    isInlined: isInlined
                )
            }
        }

        return DWARFInlineFrame(
            function: functionName,
            file: "",
            line: 0,
            column: 0,
            isInlined: isInlined
        )
    }

    private func inlineCallSite(
        for die: DWARFDie,
        lineTable: DWARFLineTable
    ) throws -> (file: String, line: UInt64, column: UInt64)? {
        guard let callFileAttr = try die.attribute(UInt16(DW_AT_call_file)) else {
            return nil
        }
        guard let fileIndex = callFileAttr.unsignedValue,
              let filePath = lineTable.filePath(forFileIndex: fileIndex) else {
            return nil
        }

        let callLineAttr = try die.attribute(UInt16(DW_AT_call_line))
        let callColumnAttr = try die.attribute(UInt16(DW_AT_call_column))
        let callLine = callLineAttr?.unsignedValue ?? 0
        let callColumn = callColumnAttr?.unsignedValue ?? 0

        return (
            file: filePath,
            line: callLine,
            column: callColumn
        )
    }

    private func dieContains(_ die: DWARFDie, address: UInt64) throws -> Bool {
        if let low = try die.lowPC(), let high = try die.highPC(), high > low {
            if (low..<high).contains(address) {
                return true
            }
        }
        let ranges = try die.addressRanges()
        if ranges.contains(where: { $0.contains(address) }) {
            return true
        }
        return false
    }

    private func handleSymbolicationError(
        _ error: Error,
        context: String,
        address: UInt64,
        options: SymbolicationOptions,
        issues: inout [DWARFSymbolicationIssue]
    ) throws {
        switch options.errorPolicy {
        case .strict:
            throw error
        case .lenient:
            issues.append(DWARFSymbolicationIssue(address: address, context: context, error: error))
        }
    }
}
