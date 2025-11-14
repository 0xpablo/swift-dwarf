import CLibdwarf

/// A DWARF compilation unit containing debug information for a single source file.
///
/// A compilation unit (CU) is the fundamental organizational unit in DWARF debug information.
/// Each CU typically corresponds to a single source file and contains all the debug
/// information entries (DIEs) for the types, functions, and variables defined in that file.
///
/// ## Overview
///
/// Access compilation units through a ``DWARFSession``:
///
/// ```swift
/// for unit in session.compilationUnits() {
///     // Access the root DIE
///     if let name = try unit.die.name() {
///         print("Compilation unit: \(name)")
///     }
///
///     // Get line table for source location mapping
///     if let lineTable = try unit.lineTable() {
///         // Use line table for address-to-source mapping
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Accessing Unit Information
/// - ``header``
/// - ``die``
/// - ``offset``
///
/// ### Working with Line Tables
/// - ``lineTable()``
public struct DWARFCompilationUnit {
    public struct Header {
        /// The DWARF version stored in the CU header.
        public let version: UInt16
        /// The number of bytes occupied by the header itself.
        public let headerLength: UInt64
        /// Offset into `.debug_abbrev` for this unit.
        public let abbreviationOffset: UInt64
        /// Size in bytes of each encoded address in this unit.
        public let addressSize: UInt16
        /// Size of DWARF offsets used in the unit.
        public let offsetSize: UInt16
        /// Size of the DWARF extension field (DWARF64 uses 8).
        public let extensionSize: UInt16
        /// Signature present for DWARF type units.
        public let typeSignature: DWARFSignature?
        /// Offset to the referenced type within `.debug_types` (if any).
        public let typeOffset: UInt64?
        /// File offset to the next compilation unit header.
        public let nextUnitOffset: UInt64
        /// Encoded unit type (`DW_UT_*`).
        public let unitType: UInt16
        /// The section that backs this compilation unit.
        public let section: DWARFSection
    }

    public let header: Header
    public let die: DWARFDie
    /// Offset within the DWARF section for this compilation unit's root DIE.
    public let offset: UInt64
}

extension DWARFCompilationUnit {
    /// Retrieves the line number table for this compilation unit.
    ///
    /// The line table maps machine code addresses to source file locations,
    /// enabling address-to-source symbolication. This is essential for debugging
    /// and crash report analysis.
    ///
    /// - Returns: A ``DWARFLineTable`` if line number information exists, or `nil`
    ///            if this compilation unit has no line table (e.g., compiled without `-g`).
    ///
    /// - Throws: ``DWARFError`` if there's an error reading the line table data.
    ///
    /// ## Example
    ///
    /// ```swift
    /// if let lineTable = try unit.lineTable() {
    ///     // Find source location for an address
    ///     if let location = lineTable.location(for: 0x100000f30) {
    ///         print("\(location.file):\(location.line):\(location.column)")
    ///     }
    /// }
    /// ```
    public func lineTable() throws -> DWARFLineTable? {
        let session = try die.owningSession()
        let key = session.makeCompilationUnitKey(for: self)
        if let cached = session.cachedLineTable(for: key) {
            return cached
        }

        var version: Dwarf_Unsigned = 0
        var tableCount: Dwarf_Small = 0
        var context: Dwarf_Line_Context?
        var error: Dwarf_Error?
        let result = dwarf_srclines_b(
            die.raw,
            &version,
            &tableCount,
            &context,
            &error
        )

        switch result {
        case DW_DLV_NO_ENTRY:
            return nil
        case DW_DLV_ERROR:
            let handle = try die.owningSession().borrowHandle()
            throw DWARFError.consume(debug: handle, error: error)
        default:
            break
        }

        guard let context else {
            let handle = try die.owningSession().borrowHandle()
            throw DWARFError.consume(debug: handle, error: error)
        }

        defer {
            dwarf_srclines_dealloc_b(context)
        }

        let handle = try die.owningSession().borrowHandle()
        let filePaths: [UInt64: String]
        do {
            filePaths = try buildLineTableFilePaths(
                context: context,
                version: UInt64(version),
                handle: handle
            )
        } catch {
            filePaths = [:]
        }

        var lineCollections: [(UnsafeMutablePointer<Dwarf_Line?>?, Dwarf_Signed, Bool)] = []

        if tableCount == 0 {
            // No lines to process.
        } else if tableCount == 1 {
            var lineBuffer: UnsafeMutablePointer<Dwarf_Line?>?
            var lineCount: Dwarf_Signed = 0
            let linesResult = dwarf_srclines_from_linecontext(
                context,
                &lineBuffer,
                &lineCount,
                &error
            )

            guard linesResult == DW_DLV_OK else {
                throw DWARFError.consume(debug: handle, error: error)
            }
            lineCollections.append((lineBuffer, lineCount, false))
        } else {
            var logicalBuffer: UnsafeMutablePointer<Dwarf_Line?>?
            var logicalCount: Dwarf_Signed = 0
            var actualBuffer: UnsafeMutablePointer<Dwarf_Line?>?
            var actualCount: Dwarf_Signed = 0

            let result = dwarf_srclines_two_level_from_linecontext(
                context,
                &logicalBuffer,
                &logicalCount,
                &actualBuffer,
                &actualCount,
                &error
            )

            guard result == DW_DLV_OK else {
                throw DWARFError.consume(debug: handle, error: error)
            }

            lineCollections.append((logicalBuffer, logicalCount, false))
            lineCollections.append((actualBuffer, actualCount, true))
        }

        var rows: [DWARFLineTable.Row] = []
        rows.reserveCapacity(256)

        func appendRows(
            from buffer: UnsafeMutablePointer<Dwarf_Line?>?,
            count: Dwarf_Signed,
            isActual: Bool
        ) throws {
            guard let buffer, count > 0 else { return }
            for index in 0..<Int(count) {
                guard let line = buffer[index] else { continue }
                var address: Dwarf_Addr = 0
                var lineNumber: Dwarf_Unsigned = 0
                var column: Dwarf_Unsigned = 0
                var isStatement: Dwarf_Bool = 0
                var isEndSequence: Dwarf_Bool = 0
                var decodeError: Dwarf_Error?
                guard dwarf_lineaddr(line, &address, &decodeError) == DW_DLV_OK,
                      dwarf_lineno(line, &lineNumber, &decodeError) == DW_DLV_OK,
                      dwarf_lineoff_b(line, &column, &decodeError) == DW_DLV_OK,
                      dwarf_linebeginstatement(line, &isStatement, &decodeError) == DW_DLV_OK,
                      dwarf_lineendsequence(line, &isEndSequence, &decodeError) == DW_DLV_OK else {
                    throw DWARFError.consume(debug: handle, error: decodeError)
                }

                let (filePath, indexValue) = try resolveLineTableFile(
                    for: line,
                    filePaths: filePaths,
                    handle: handle
                )

                rows.append(
                    DWARFLineTable.Row(
                        address: UInt64(address),
                        file: filePath,
                        fileIndex: indexValue,
                        line: UInt64(lineNumber),
                        column: UInt64(column),
                        isStatement: isStatement != 0,
                        isEndSequence: isEndSequence != 0,
                        isActual: isActual
                    )
                )
            }
        }

        for (buffer, count, isActual) in lineCollections {
            try appendRows(from: buffer, count: count, isActual: isActual)
        }

        let table = DWARFLineTable(
            version: UInt64(version),
            rows: rows,
            filePaths: filePaths
        )
        session.cacheLineTable(table, for: key)
        return table
    }

    private func buildLineTableFilePaths(
        context: Dwarf_Line_Context,
        version: UInt64,
        handle: Dwarf_Debug
    ) throws -> [UInt64: String] {
        let directories = try buildLineTableDirectories(
            context: context,
            version: version,
            handle: handle
        )
        let compileDirectory = try? die.attribute(UInt16(DW_AT_comp_dir))?.stringValue
        return try buildLineTableFiles(
            context: context,
            directories: directories,
            compileDirectory: compileDirectory,
            handle: handle
        )
    }

    private func buildLineTableDirectories(
        context: Dwarf_Line_Context,
        version: UInt64,
        handle: Dwarf_Debug
    ) throws -> [UInt64: String] {
        var count: Dwarf_Signed = 0
        var error: Dwarf_Error?
        let countResult = dwarf_srclines_include_dir_count(
            context,
            &count,
            &error
        )

        switch countResult {
        case DW_DLV_NO_ENTRY:
            return [:]
        case DW_DLV_OK:
            break
        default:
            throw DWARFError.consume(debug: handle, error: error)
        }

        guard count > 0 else { return [:] }

        let startIndex: Dwarf_Signed = version >= 5 ? 0 : 1
        let endIndex: Dwarf_Signed = version >= 5 ? count : count + startIndex
        guard startIndex < endIndex else { return [:] }

        var directories: [UInt64: String] = [:]
        directories.reserveCapacity(Int(endIndex - startIndex))

        for index in startIndex..<endIndex {
            var directoryPointer: UnsafePointer<CChar>?
            var dirError: Dwarf_Error?
            let entryResult = dwarf_srclines_include_dir_data(
                context,
                index,
                &directoryPointer,
                &dirError
            )
            switch entryResult {
            case DW_DLV_NO_ENTRY:
                continue
            case DW_DLV_OK:
                if let directoryPointer {
                    directories[UInt64(index)] = String(cString: directoryPointer)
                }
            default:
                throw DWARFError.consume(debug: handle, error: dirError)
            }
        }

        return directories
    }

    private func buildLineTableFiles(
        context: Dwarf_Line_Context,
        directories: [UInt64: String],
        compileDirectory: String?,
        handle: Dwarf_Debug
    ) throws -> [UInt64: String] {
        var baseIndex: Dwarf_Signed = 0
        var count: Dwarf_Signed = 0
        var endIndex: Dwarf_Signed = 0
        var error: Dwarf_Error?
        let indexResult = dwarf_srclines_files_indexes(
            context,
            &baseIndex,
            &count,
            &endIndex,
            &error
        )

        switch indexResult {
        case DW_DLV_NO_ENTRY:
            return [:]
        case DW_DLV_OK:
            break
        default:
            throw DWARFError.consume(debug: handle, error: error)
        }

        guard count > 0, baseIndex < endIndex else { return [:] }

        var files: [UInt64: String] = [:]
        files.reserveCapacity(Int(count))

        for index in baseIndex..<endIndex {
            var namePointer: UnsafePointer<CChar>?
            var directoryIndex: Dwarf_Unsigned = 0
            var entryError: Dwarf_Error?
            let entryResult = dwarf_srclines_files_data_b(
                context,
                index,
                &namePointer,
                &directoryIndex,
                nil,
                nil,
                nil,
                &entryError
            )
            switch entryResult {
            case DW_DLV_NO_ENTRY:
                continue
            case DW_DLV_OK:
                guard let namePointer else { continue }
                let fileName = String(cString: namePointer)
                let directory = directories[UInt64(directoryIndex)]
                let resolved = resolveLineTablePath(
                    directory: directory,
                    compileDirectory: compileDirectory,
                    fileName: fileName
                )
                files[UInt64(index)] = resolved
            default:
                throw DWARFError.consume(debug: handle, error: entryError)
            }
        }

        return files
    }

    private func resolveLineTableFile(
        for line: Dwarf_Line,
        filePaths: [UInt64: String],
        handle: Dwarf_Debug
    ) throws -> (String, UInt64?) {
        var fileNumber: Dwarf_Unsigned = 0
        var error: Dwarf_Error?
        let fileResult = dwarf_line_srcfileno(line, &fileNumber, &error)
        guard fileResult == DW_DLV_OK else {
            throw DWARFError.consume(debug: handle, error: error)
        }

        let fileIndex = UInt64(fileNumber)
        if let path = filePaths[fileIndex] {
            return (path, fileIndex)
        }

        var pointer: UnsafeMutablePointer<CChar>?
        let pathResult = dwarf_linesrc(line, &pointer, &error)
        guard pathResult == DW_DLV_OK, let pointer else {
            if pathResult == DW_DLV_NO_ENTRY {
                return ("", nil)
            }
            throw DWARFError.consume(debug: handle, error: error)
        }
        defer {
            dwarf_dealloc(handle, pointer, Dwarf_Unsigned(DW_DLA_STRING))
        }
        return (String(cString: pointer), fileIndex)
    }

    private func resolveLineTablePath(
        directory: String?,
        compileDirectory: String?,
        fileName: String
    ) -> String {
        if fileName.hasPrefix("/") {
            return fileName
        }

        let base = directory ?? compileDirectory
        guard let base, !base.isEmpty else {
            return fileName
        }

        if base.hasSuffix("/") {
            return base + fileName
        }
        return base + "/" + fileName
    }

    /// Returns the first subprogram DIE covering the specified address, if any.
    public func subprogram(at address: UInt64) throws -> DWARFDie? {
        var stack: [DWARFDie] = [die]
        while let current = stack.popLast() {
            if (try? current.tag()) == UInt16(DW_TAG_subprogram),
               contains(address: address, in: current) {
                return current
            }
            var iterator = current.children().makeIterator()
            while let child = iterator.next() {
                stack.append(child)
            }
            if let error = iterator.error {
                throw error
            }
        }
        return nil
    }

    /// Returns the function name for the specified address, if available.
    /// Attempts to return a demangled name with full signature (e.g., "greet(name:)").
    /// - Note: The core DWARF module only uses DW_AT_name/DW_AT_linkage_name and
    ///   does not perform demangling. For Swift/C++ demangling, depend on the
    ///   DWARFSymbolication module.
    public func functionName(at address: UInt64) throws -> String? {
        try subprogram(at: address)?.displayName()
    }

    private func contains(address: UInt64, in die: DWARFDie) -> Bool {
        if let low = try? die.lowPC(), let high = try? die.highPC(),
           high > low {
            return (low..<high).contains(address)
        }
        if let ranges = try? die.addressRanges(), !ranges.isEmpty {
            return ranges.contains(where: { $0.contains(address) })
        }
        return false
    }
}

/// Iterates compilation units in a given DWARF section.
public struct DWARFCompilationUnitIterator: IteratorProtocol {
    private let session: DWARFSession
    private let section: DWARFSection
    private var finished = false

    init(session: DWARFSession, section: DWARFSection) {
        self.session = session
        self.section = section
    }

    /// Advances to the next compilation unit.
    public mutating func next() -> DWARFCompilationUnit? {
        guard error == nil, !finished else { return nil }

        var diePointer: Dwarf_Die?
        var headerLength: Dwarf_Unsigned = 0
        var version: Dwarf_Half = 0
        var abbrevOffset: Dwarf_Off = 0
        var addressSize: Dwarf_Half = 0
        var lengthSize: Dwarf_Half = 0
        var extensionSize: Dwarf_Half = 0
        var signature = Dwarf_Sig8()
        var typeOffset: Dwarf_Unsigned = 0
        var nextHeaderOffset: Dwarf_Unsigned = 0
        var headerUnitType: Dwarf_Half = 0
        var error: Dwarf_Error?

        do {
            let result: Int32 = try session.withHandle { handle in
                dwarf_next_cu_header_e(
                    handle,
                    section.isInfoFlag,
                    &diePointer,
                    &headerLength,
                    &version,
                    &abbrevOffset,
                    &addressSize,
                    &lengthSize,
                    &extensionSize,
                    &signature,
                    &typeOffset,
                    &nextHeaderOffset,
                    &headerUnitType,
                    &error
                )
            }

            switch result {
            case DW_DLV_OK:
                guard let diePointer else {
                    finished = true
                    return nil
                }

                var dieOffset: Dwarf_Off = 0
                var offsetError: Dwarf_Error?
                guard dwarf_dieoffset(diePointer, &dieOffset, &offsetError) == DW_DLV_OK else {
                    finished = true
                    let handle = try session.borrowHandle()
                    throw DWARFError.consume(debug: handle, error: offsetError)
                }

                let header = DWARFCompilationUnit.Header(
                    version: UInt16(version),
                    headerLength: UInt64(headerLength),
                    abbreviationOffset: UInt64(abbrevOffset),
                    addressSize: UInt16(addressSize),
                    offsetSize: UInt16(lengthSize),
                    extensionSize: UInt16(extensionSize),
                    typeSignature: DWARFSignature(rawSignature: signature),
                    typeOffset: typeOffset == 0 ? nil : UInt64(typeOffset),
                    nextUnitOffset: UInt64(nextHeaderOffset),
                    unitType: UInt16(headerUnitType),
                    section: section
                )

                let die = DWARFDie(session: session, raw: diePointer)
                return DWARFCompilationUnit(
                    header: header,
                    die: die,
                    offset: UInt64(dieOffset)
                )

            case DW_DLV_NO_ENTRY:
                finished = true
                return nil

            default:
                finished = true
                let handle = try session.borrowHandle()
                throw DWARFError.consume(debug: handle, error: error)
            }
        } catch {
            finished = true
            self.error = error
            return nil
        }
    }

    public private(set) var error: Error?
}

/// Sequence wrapper providing idiomatic iteration over compilation units.
public struct DWARFCompilationUnitSequence: Sequence {
    private let session: DWARFSession
    private let section: DWARFSection

    init(session: DWARFSession, section: DWARFSection) {
        self.session = session
        self.section = section
    }

    public func makeIterator() -> DWARFCompilationUnitIterator {
        DWARFCompilationUnitIterator(session: session, section: section)
    }
}

/// Represents the 8-byte type signature used by DWARF split/type units.
public struct DWARFSignature: Hashable, Sendable, CustomStringConvertible {
    private let value: UInt64

    init(value: UInt64) {
        self.value = value
    }

    init?(rawSignature: Dwarf_Sig8) {
        let value = withUnsafeBytes(of: rawSignature.signature) { buffer -> UInt64 in
            var aggregate: UInt64 = 0
            for (index, byte) in buffer.enumerated() {
                aggregate |= UInt64(byte) << (UInt64(index) * 8)
            }
            return aggregate
        }
        guard value != 0 else { return nil }
        self.init(value: value)
    }

    /// Raw bytes composing the signature in little-endian order.
    public var bytes: [UInt8] {
        (0..<8).map { UInt8(truncatingIfNeeded: value >> (UInt64($0) * 8)) }
    }

    public var description: String {
        let symbols: [Character] = Array("0123456789ABCDEF")
        var scalars: [Character] = []
        scalars.reserveCapacity(16)
        for byte in bytes {
            scalars.append(symbols[Int(byte >> 4)])
            scalars.append(symbols[Int(byte & 0x0F)])
        }
        return String(scalars)
    }
}
