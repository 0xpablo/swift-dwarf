import CLibdwarf
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A session for reading DWARF debugging information from binaries.
///
/// `DWARFSession` is the main entry point for parsing DWARF data from executables,
/// shared libraries, object files, or dSYM bundles. It manages the underlying
/// libdwarf resources and provides type-safe Swift APIs for accessing debug information.
///
/// ## Overview
///
/// Create a session by providing a path to a binary containing DWARF data:
///
/// ```swift
/// let session = try DWARFSession(path: "/path/to/binary.dSYM")
/// defer { session.close() }
///
/// // Access compilation units
/// for unit in session.compilationUnits() {
///     print("Processing unit at offset: \(unit.offset)")
/// }
/// ```
///
/// ## Topics
///
/// ### Creating a Session
/// - ``init(path:options:)``
/// - ``Options``
///
/// ### Accessing Debug Information
/// - ``compilationUnits(section:)``
/// - ``compilationUnit(at:section:)``
/// - ``objectInfo()``
///
/// ### Session Management
/// - ``close()``
/// - ``isClosed``
///
/// - Important: `DWARFSession` is **not** thread-safe. All methods must be used
///   on the same actor/queue/thread that created the session, because libdwarf
///   performs no internal synchronization.
public final class DWARFSession {
    /// Configuration options for opening a DWARF session.
    ///
    /// Use these options to control architecture selection for universal binaries
    /// and specify additional search paths for separate debug files.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Select ARM64 slice from a universal binary
    /// let options = DWARFSession.Options(architectureIndex: 1)
    /// let session = try DWARFSession(path: "/path/to/universal/binary", options: options)
    /// ```
    public struct Options {
        /// Additional search paths for locating separate debug files.
        ///
        /// These paths are consulted when resolving `.gnu_debuglink` references
        /// on Linux systems that store debug symbols separately.
        public var searchPaths: [String]

        /// DWARF section group identifier.
        ///
        /// Defaults to `DW_GROUPNUMBER_ANY` to read all groups.
        /// Rarely needs to be changed.
        public var groupNumber: UInt32

        /// Architecture index for Mach-O universal binaries.
        ///
        /// For universal (fat) binaries containing multiple architectures,
        /// specify the zero-based index of the desired architecture slice.
        /// Defaults to 0 (first architecture).
        ///
        /// Use `otool -f` or `lipo -info` to see available architectures
        /// and their indices in a universal binary.
        public var architectureIndex: UInt32

        public init(
            searchPaths: [String] = [],
            groupNumber: UInt32 = UInt32(DW_GROUPNUMBER_ANY),
            architectureIndex: UInt32 = 0
        ) {
            self.searchPaths = searchPaths
            self.groupNumber = groupNumber
            self.architectureIndex = architectureIndex
        }
    }

    /// Errors related to session state rather than libdwarf itself.
    public enum StateError: Error, CustomStringConvertible {
        case closed
        case noDwarfData(path: String)

        public var description: String {
            switch self {
            case .closed:
                return "DWARF session is closed"
            case .noDwarfData(let path):
                return "No DWARF debug information found in '\(path)'"
            }
        }
    }

    /// Original path requested by the caller.
    public let originalPath: String
    /// Resolved object path reported by libdwarf (if available).
    public let resolvedPath: String?
    /// Source of the resolved path (matches `DW_PATHSOURCE_*` constants).
    public let pathSource: UInt8
    /// Options used to open the session.
    public let options: Options

    /// Whether the underlying libdwarf handle has been closed.
    public var isClosed: Bool { rawHandle == nil }

    private var rawHandle: Dwarf_Debug?

    private struct AddressRangeEntry {
        let lowerBound: UInt64
        let upperBound: UInt64
        let cuOffset: UInt64
    }

    struct CompilationUnitKey: Hashable {
        let section: DWARFSection
        let offset: UInt64
    }

    private var cachedCompilationUnits: [DWARFSection: [DWARFCompilationUnit]] = [:]
    private var compilationUnitsByOffset: [DWARFSection: [UInt64: DWARFCompilationUnit]] = [:]
    private var cachedCompilationUnitRanges: [CompilationUnitKey: [Range<UInt64>]] = [:]
    private var cachedAddressRanges: [AddressRangeEntry]?
    private var cachedLineTables: [CompilationUnitKey: DWARFLineTable] = [:]

    /// Creates a new DWARF session for reading debug information.
    ///
    /// - Parameters:
    ///   - path: Path to a binary file, dSYM bundle, or object file containing DWARF data.
    ///           For dSYM bundles, provide the path to the actual binary inside
    ///           `Contents/Resources/DWARF/`.
    ///   - options: Configuration options for the session, including architecture selection
    ///              for universal binaries and additional search paths.
    ///
    /// - Throws: ``DWARFError`` if the file cannot be opened or contains no DWARF data.
    ///
    /// - Note: Remember to call ``close()`` when done, or use `defer { session.close() }`
    ///         to ensure proper cleanup.
    public init(path: String, options: Options = Options()) throws {
        self.originalPath = path
        self.options = options

        var handle: Dwarf_Debug?
        var dwarfError: Dwarf_Error?
        var pathOrigin: UInt8 = 0
        var truePathBuffer = Array<CChar>(repeating: 0, count: Int(PATH_MAX) + 1)

        let result: Int32 = truePathBuffer.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return DW_DLV_ERROR
            }

            return path.withCString { cPath in
                withCStringArray(options.searchPaths) { searchPointer, searchCount in
                    dwarf_init_path_dl_a(
                        cPath,
                        baseAddress,
                        UInt32(buffer.count),
                        options.groupNumber,
                        options.architectureIndex,
                        nil,
                        nil,
                        &handle,
                        searchPointer,
                        searchCount,
                        &pathOrigin,
                        &dwarfError
                    )
                }
            }
        }

        switch result {
        case DW_DLV_OK:
            guard let handle else {
                throw DWARFError.consume(debug: nil, error: dwarfError)
            }
            rawHandle = handle
            pathSource = pathOrigin

            // Parse resolved path from buffer
            if let terminator = truePathBuffer.firstIndex(of: 0) {
                if terminator == 0 {
                    resolvedPath = nil
                } else {
                    let bytes = truePathBuffer[..<terminator].map { UInt8(bitPattern: $0) }
                    resolvedPath = String(decoding: bytes, as: UTF8.self)
                }
            } else {
                let bytes = truePathBuffer.map { UInt8(bitPattern: $0) }
                resolvedPath = String(decoding: bytes, as: UTF8.self)
            }

        case DW_DLV_NO_ENTRY:
            // Binary has no DWARF debug information
            throw StateError.noDwarfData(path: path)

        case DW_DLV_ERROR:
            // Actual error occurred
            throw DWARFError.consume(debug: handle, error: dwarfError)

        default:
            // Unknown return value
            throw DWARFError.consume(debug: handle, error: dwarfError)
        }
    }

    deinit {
        close()
    }

    /// Executes `body` with the underlying `Dwarf_Debug` handle.
    @discardableResult
    public func withHandle<Result>(_ body: (Dwarf_Debug) throws -> Result) throws -> Result {
        guard let handle = rawHandle else { throw StateError.closed }
        return try body(handle)
    }

    /// Internal helper to borrow the underlying libdwarf handle without exposing it publicly.
    func borrowHandle() throws -> Dwarf_Debug {
        guard let handle = rawHandle else { throw StateError.closed }
        return handle
    }

    /// Creates an iterator that walks all compilation units contained in the requested section.
    /// - Parameter section: Whether to iterate `.debug_info` (default) or `.debug_types`.
    /// - Returns: A stateful iterator that lazily advances through compile units as requested.
    public func makeCompilationUnitIterator(
        section: DWARFSection = .info
    ) -> DWARFCompilationUnitIterator {
        DWARFCompilationUnitIterator(session: self, section: section)
    }

    /// Returns a `Sequence` for iterating compilation units in the specified section.
    public func compilationUnits(
        section: DWARFSection = .info
    ) -> DWARFCompilationUnitSequence {
        DWARFCompilationUnitSequence(session: self, section: section)
    }

    /// Adjusts the harmless error ring buffer size for this session.
    @discardableResult
    public func setHarmlessErrorBufferSize(_ maxErrors: UInt32) throws -> UInt32 {
        try withHandle { dwarf_set_harmless_error_list_size($0, maxErrors) }
    }

    /// Releases libdwarf resources. Safe to call multiple times.
    public func close() {
        guard let handle = rawHandle else { return }
        _ = dwarf_finish(handle)
        rawHandle = nil
        resetCaches()
    }

    private func resetCaches() {
        cachedCompilationUnits.removeAll()
        compilationUnitsByOffset.removeAll()
        cachedCompilationUnitRanges.removeAll()
        cachedAddressRanges = nil
        cachedLineTables.removeAll()
    }

    /// Returns metadata describing the underlying object that the session wraps.
    public func objectInfo() throws -> DWARFObjectInfo {
        var fileType: Dwarf_Small = 0
        var pointerSize: Dwarf_Small = 0
        var bigEndian: Dwarf_Bool = 0
        var machine: Dwarf_Unsigned = 0
        var objectType: Dwarf_Unsigned = 0
        var flags: Dwarf_Unsigned = 0
        var pathSourceRaw: Dwarf_Small = 0
        var ubOffset: Dwarf_Unsigned = 0
        var ubCount: Dwarf_Unsigned = 0
        var ubIndex: Dwarf_Unsigned = 0
        var comdat: Dwarf_Unsigned = 0

        let result = try withHandle { handle in
            dwarf_machine_architecture_a(
                handle,
                &fileType,
                &pointerSize,
                &bigEndian,
                &machine,
                &objectType,
                &flags,
                &pathSourceRaw,
                &ubOffset,
                &ubCount,
                &ubIndex,
                &comdat
            )
        }

        if result == DW_DLV_NO_ENTRY {
            throw StateError.noDwarfData(path: originalPath)
        } else if result != DW_DLV_OK {
            throw DWARFError(
                code: UInt64(result),
                message: "libdwarf dwarf_machine_architecture_a failed for \(originalPath) with code \(result)"
            )
        }

        // Extract UUID if available (Mach-O LC_UUID)
        var uuid: UUID? = nil
        var uuidBytes = (UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                         UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                         UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                         UInt8(0), UInt8(0), UInt8(0), UInt8(0))
        let uuidResult = try withHandle { handle in
            withUnsafeMutableBytes(of: &uuidBytes) { buffer in
                dwarf_object_get_uuid(handle, buffer.baseAddress)
            }
        }
        if uuidResult == DW_DLV_OK {
            uuid = UUID(uuid: uuidBytes)
        }

        return DWARFObjectInfo(
            fileType: DWARFFileType(rawValue: fileType) ?? .unknown,
            pointerSize: pointerSize,
            isBigEndian: bigEndian != 0,
            machineIdentifier: machine,
            objectTypeCode: objectType,
            flags: flags,
            pathSource: DWARFPathSource(rawValue: pathSourceRaw) ?? .unspecified,
            universalBinaryOffset: ubOffset,
            universalBinaryCount: ubCount,
            universalBinaryIndex: ubIndex,
            comdatGroupNumber: comdat,
            uuid: uuid
        )
    }

    public func compilationUnit(
        containing address: UInt64,
        section: DWARFSection = .info
    ) throws -> DWARFCompilationUnit? {
        if section == .info, let entry = try findAddressRange(for: address),
           let unit = try compilationUnit(withOffset: entry.cuOffset, section: section) {
            return unit
        }

        for unit in try cachedUnits(in: section) {
            if try unitContains(address: address, unit: unit) {
                return unit
            }
        }
        return nil
    }

    private func cachedUnits(in section: DWARFSection) throws -> [DWARFCompilationUnit] {
        if let cached = cachedCompilationUnits[section] {
            return cached
        }

        var iterator = makeCompilationUnitIterator(section: section)
        var units: [DWARFCompilationUnit] = []
        while let unit = iterator.next() {
            units.append(unit)
        }
        if let error = iterator.error {
            throw error
        }
        cachedCompilationUnits[section] = units

        var offsetMap: [UInt64: DWARFCompilationUnit] = [:]
        offsetMap.reserveCapacity(units.count)
        for unit in units {
            offsetMap[unit.offset] = unit
        }
        compilationUnitsByOffset[section] = offsetMap
        return units
    }

    private func compilationUnit(
        withOffset offset: UInt64,
        section: DWARFSection
    ) throws -> DWARFCompilationUnit? {
        if let cached = compilationUnitsByOffset[section]?[offset] {
            return cached
        }
        return try cachedUnits(in: section).first(where: { $0.offset == offset })
    }

    private func ensureAddressRangeTable() throws -> [AddressRangeEntry] {
        if let cached = cachedAddressRanges {
            return cached
        }

        let handle = try borrowHandle()
        var arangeBuffer: UnsafeMutablePointer<Dwarf_Arange?>?
        var count: Dwarf_Signed = 0
        var error: Dwarf_Error?
        let result = dwarf_get_aranges(
            handle,
            &arangeBuffer,
            &count,
            &error
        )

        switch result {
        case DW_DLV_NO_ENTRY:
            cachedAddressRanges = []
            return []
        case DW_DLV_OK:
            break
        default:
            throw DWARFError.consume(debug: handle, error: error)
        }

        guard let arangeBuffer, count > 0 else {
            cachedAddressRanges = []
            return []
        }

        let entryCount = Int(count)
        var entries: [AddressRangeEntry] = []
        entries.reserveCapacity(entryCount)

        defer {
            for index in 0..<entryCount {
                if let arange = arangeBuffer[index] {
                    dwarf_dealloc(handle, UnsafeMutableRawPointer(arange), Dwarf_Unsigned(DW_DLA_ARANGE))
                }
            }
            dwarf_dealloc(handle, UnsafeMutableRawPointer(arangeBuffer), Dwarf_Unsigned(DW_DLA_LIST))
        }

        for index in 0..<entryCount {
            guard let arange = arangeBuffer[index] else {
                continue
            }

            var segment: Dwarf_Unsigned = 0
            var segmentEntrySize: Dwarf_Unsigned = 0
            var start: Dwarf_Addr = 0
            var length: Dwarf_Unsigned = 0
            var cuOffset: Dwarf_Off = 0
            var infoError: Dwarf_Error?
            let infoResult = dwarf_get_arange_info_b(
                arange,
                &segment,
                &segmentEntrySize,
                &start,
                &length,
                &cuOffset,
                &infoError
            )
            guard infoResult == DW_DLV_OK else {
                throw DWARFError.consume(debug: handle, error: infoError)
            }

            let length64 = UInt64(length)
            guard length64 != 0 else { continue }
            let lower = UInt64(start)
            let upper = lower &+ length64
            guard upper >= lower else { continue }
            entries.append(
                AddressRangeEntry(
                    lowerBound: lower,
                    upperBound: upper,
                    cuOffset: UInt64(cuOffset)
                )
            )
        }

        entries.sort { $0.lowerBound < $1.lowerBound }
        cachedAddressRanges = entries
        return entries
    }

    private func findAddressRange(for address: UInt64) throws -> AddressRangeEntry? {
        let ranges = try ensureAddressRangeTable()
        guard !ranges.isEmpty else { return nil }

        var low = 0
        var high = ranges.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let entry = ranges[mid]
            if address < entry.lowerBound {
                if mid == 0 { break }
                high = mid - 1
            } else if address >= entry.upperBound {
                low = mid + 1
            } else {
                return entry
            }
        }
        return nil
    }

    private func unitContains(address: UInt64, unit: DWARFCompilationUnit) throws -> Bool {
        let ranges = try cachedRanges(for: unit)
        return ranges.contains(where: { $0.contains(address) })
    }

    private func cachedRanges(for unit: DWARFCompilationUnit) throws -> [Range<UInt64>] {
        let key = makeCompilationUnitKey(for: unit)
        if let cached = cachedCompilationUnitRanges[key] {
            return cached
        }

        let ranges = try unit.die.addressRanges()
        cachedCompilationUnitRanges[key] = ranges
        return ranges
    }

    func cachedLineTable(for key: CompilationUnitKey) -> DWARFLineTable? {
        cachedLineTables[key]
    }

    func cacheLineTable(_ table: DWARFLineTable, for key: CompilationUnitKey) {
        cachedLineTables[key] = table
    }

    func makeCompilationUnitKey(for unit: DWARFCompilationUnit) -> CompilationUnitKey {
        CompilationUnitKey(section: unit.header.section, offset: unit.offset)
    }

    func decodeAttribute(_ attribute: Dwarf_Attribute?) throws -> DWARFAttribute? {
        guard let attribute else { return nil }
        var code: Dwarf_Half = 0
        var form: Dwarf_Half = 0
        var error: Dwarf_Error?
        guard let handle = rawHandle else { throw StateError.closed }

        guard dwarf_whatattr(attribute, &code, &error) == DW_DLV_OK,
              dwarf_whatform(attribute, &form, &error) == DW_DLV_OK else {
            let rawPointer = UnsafeMutableRawPointer(mutating: UnsafeRawPointer(attribute))
            dwarf_dealloc(handle, rawPointer, Dwarf_Unsigned(DW_DLA_ATTR))
            throw DWARFError.consume(debug: handle, error: error)
        }

        let value = decodeAttributeValue(attribute: attribute, form: form)
        let rawPointer = UnsafeMutableRawPointer(mutating: UnsafeRawPointer(attribute))
        dwarf_dealloc(handle, rawPointer, Dwarf_Unsigned(DW_DLA_ATTR))
        return DWARFAttribute(code: code, form: form, value: value)
    }

    private func decodeAttributeValue(attribute: Dwarf_Attribute, form: Dwarf_Half) -> DWARFAttributeValue {
        var error: Dwarf_Error?
        let formValue = Int32(form)
        switch formValue {
        case DW_FORM_string, DW_FORM_strp, DW_FORM_strx, DW_FORM_line_strp, DW_FORM_strp_sup, DW_FORM_GNU_strp_alt:
            var pointer: UnsafeMutablePointer<CChar>?
            if dwarf_formstring(attribute, &pointer, &error) == DW_DLV_OK, let pointer {
                let result = String(cString: pointer)
                // Note: dwarf_formstring returns strings that should NOT be deallocated
                // They are managed by libdwarf and remain valid for the life of the Dwarf_Debug
                return .string(result)
            }
        case DW_FORM_addr, DW_FORM_addrx, DW_FORM_GNU_addr_index:
            var addr: Dwarf_Addr = 0
            if dwarf_formaddr(attribute, &addr, &error) == DW_DLV_OK {
                return .address(UInt64(addr))
            }
        case DW_FORM_data1, DW_FORM_data2, DW_FORM_data4, DW_FORM_data8, DW_FORM_udata:
            var value: Dwarf_Unsigned = 0
            if dwarf_formudata(attribute, &value, &error) == DW_DLV_OK {
                return .unsigned(UInt64(value))
            }
        case DW_FORM_sdata:
            var signedValue: Dwarf_Signed = 0
            if dwarf_formsdata(attribute, &signedValue, &error) == DW_DLV_OK {
                return .signed(Int64(signedValue))
            }
        case DW_FORM_flag, DW_FORM_flag_present:
            var flag: Dwarf_Bool = 0
            if dwarf_formflag(attribute, &flag, &error) == DW_DLV_OK {
                return .flag(flag != 0)
            }
        case DW_FORM_ref1, DW_FORM_ref2, DW_FORM_ref4, DW_FORM_ref8,
             DW_FORM_ref_udata, DW_FORM_ref_addr, DW_FORM_ref_sig8, DW_FORM_GNU_ref_alt:
            var offset: Dwarf_Off = 0
            var isInfo: Dwarf_Bool = 0
            if dwarf_formref(attribute, &offset, &isInfo, &error) == DW_DLV_OK {
                return .reference(UInt64(offset))
            }
        default:
            break
        }
        return .unsupported
    }

    func deallocateAttributeList(_ pointer: UnsafeMutablePointer<Dwarf_Attribute?>) {
        guard let handle = rawHandle else { return }
        dwarf_dealloc(handle, UnsafeMutableRawPointer(pointer), Dwarf_Unsigned(DW_DLA_LIST))
    }

    func fetchRanges(for die: DWARFDie) throws -> [Range<UInt64>]? {
        guard let handle = rawHandle else { throw StateError.closed }

        if let rnglistRanges = try fetchRnglistRanges(for: die, handle: handle) {
            return rnglistRanges
        }

        var baseKnown: Dwarf_Bool = 0
        var baseAddress: Dwarf_Unsigned = 0
        var hasRanges: Dwarf_Bool = 0
        var rangesOffset: Dwarf_Unsigned = 0
        var error: Dwarf_Error?
        let baseResult = dwarf_get_ranges_baseaddress(
            handle,
            die.raw,
            &baseKnown,
            &baseAddress,
            &hasRanges,
            &rangesOffset,
            &error
        )
        guard baseResult == DW_DLV_OK else {
            throw DWARFError.consume(debug: handle, error: error)
        }
        guard hasRanges != 0 else {
            return nil
        }

        var realOffset: Dwarf_Off = 0
        var rangesBuffer: UnsafeMutablePointer<Dwarf_Ranges>?
        var rangeCount: Dwarf_Signed = 0
        var byteCount: Dwarf_Unsigned = 0
        let rangesResult = dwarf_get_ranges_b(
            handle,
            Dwarf_Off(rangesOffset),
            die.raw,
            &realOffset,
            &rangesBuffer,
            &rangeCount,
            &byteCount,
            &error
        )
        guard rangesResult == DW_DLV_OK, let rangesBuffer else {
            throw DWARFError.consume(debug: handle, error: error)
        }
        defer {
            dwarf_dealloc_ranges(handle, rangesBuffer, rangeCount)
        }

        var computed: [Range<UInt64>] = []
        computed.reserveCapacity(Int(rangeCount))
        var currentBase = baseKnown != 0 ? baseAddress : 0
        outer: for index in 0..<Int(rangeCount) {
            let entry = rangesBuffer[index]
            switch entry.dwr_type {
            case DW_RANGES_ENTRY:
                let low = currentBase &+ entry.dwr_addr1
                let high = currentBase &+ entry.dwr_addr2
                if high > low {
                    computed.append(UInt64(low)..<UInt64(high))
                }
            case DW_RANGES_ADDRESS_SELECTION:
                currentBase = entry.dwr_addr2
            case DW_RANGES_END:
                break outer
            default:
                continue
            }
        }
        return computed
    }

    private func fetchRnglistRanges(
        for die: DWARFDie,
        handle: Dwarf_Debug
    ) throws -> [Range<UInt64>]? {
        var attributePointer: Dwarf_Attribute?
        var error: Dwarf_Error?
        let attributeResult = dwarf_attr(
            die.raw,
            UInt16(DW_AT_ranges),
            &attributePointer,
            &error
        )

        switch attributeResult {
        case DW_DLV_NO_ENTRY:
            return nil
        case DW_DLV_OK:
            break
        default:
            throw DWARFError.consume(debug: handle, error: error)
        }

        guard let attributePointer else { return nil }
        defer {
            dwarf_dealloc(
                handle,
                UnsafeMutableRawPointer(attributePointer),
                Dwarf_Unsigned(DW_DLA_ATTR)
            )
        }

        var form: Dwarf_Half = 0
        guard dwarf_whatform(attributePointer, &form, &error) == DW_DLV_OK else {
            throw DWARFError.consume(debug: handle, error: error)
        }

        let formValue = Int32(form)
        guard formValue == DW_FORM_sec_offset || formValue == DW_FORM_rnglistx else {
            return nil
        }

        // DW_AT_ranges can be encoded either as a section offset into .debug_rnglists
        // (DW_FORM_sec_offset) or as an index into the rnglists table (DW_FORM_rnglistx).
        // libdwarf expects callers to decode DW_FORM_sec_offset using dwarf_global_formref.
        var attributeValue: Dwarf_Unsigned = 0
        if formValue == DW_FORM_sec_offset {
            var offset: Dwarf_Off = 0
            guard dwarf_global_formref(attributePointer, &offset, &error) == DW_DLV_OK else {
                throw DWARFError.consume(debug: handle, error: error)
            }
            attributeValue = Dwarf_Unsigned(offset)
        } else {
            guard dwarf_formudata(attributePointer, &attributeValue, &error) == DW_DLV_OK else {
                throw DWARFError.consume(debug: handle, error: error)
            }
        }

        var rnglistHead: Dwarf_Rnglists_Head?
        var entryCount: Dwarf_Unsigned = 0
        var globalOffset: Dwarf_Unsigned = 0
        let headResult = dwarf_rnglists_get_rle_head(
            attributePointer,
            form,
            attributeValue,
            &rnglistHead,
            &entryCount,
            &globalOffset,
            &error
        )

        switch headResult {
        case DW_DLV_NO_ENTRY:
            return nil
        case DW_DLV_OK:
            break
        default:
            throw DWARFError.consume(debug: handle, error: error)
        }

        guard let rnglistHead else { return nil }
        defer {
            dwarf_dealloc_rnglists_head(rnglistHead)
        }

        guard entryCount > 0 else {
            return []
        }

        var ranges: [Range<UInt64>] = []
        ranges.reserveCapacity(Int(entryCount))
        var debugAddrUnavailable = Dwarf_Bool(0)

        outer: for entryIndex in 0..<Int(entryCount) {
            var entryLength = UInt32(0)
            var rleCode = UInt32(0)
            var raw1: Dwarf_Unsigned = 0
            var raw2: Dwarf_Unsigned = 0
            var cooked1: Dwarf_Unsigned = 0
            var cooked2: Dwarf_Unsigned = 0
            debugAddrUnavailable = 0

            let entryResult = dwarf_get_rnglists_entry_fields_a(
                rnglistHead,
                Dwarf_Unsigned(entryIndex),
                &entryLength,
                &rleCode,
                &raw1,
                &raw2,
                &debugAddrUnavailable,
                &cooked1,
                &cooked2,
                &error
            )

            guard entryResult == DW_DLV_OK else {
                throw DWARFError.consume(debug: handle, error: error)
            }

            guard debugAddrUnavailable == 0 else {
                throw DWARFError(code: 0, message: "DWARF rnglists entry requires .debug_addr data that is unavailable.")
            }

            switch rleCode {
            case UInt32(DW_RLE_end_of_list):
                break outer

            case UInt32(DW_RLE_start_end),
                 UInt32(DW_RLE_startx_endx),
                 UInt32(DW_RLE_offset_pair):
                let low = UInt64(cooked1)
                let high = UInt64(cooked2)
                if high > low {
                    ranges.append(low..<high)
                }

            case UInt32(DW_RLE_start_length),
                 UInt32(DW_RLE_startx_length):
                let low = UInt64(cooked1)
                let length = UInt64(raw2)
                if length > 0 {
                    let high = low &+ length
                    if high > low {
                        ranges.append(low..<high)
                    }
                }

            case UInt32(DW_RLE_base_address),
                 UInt32(DW_RLE_base_addressx):
                // Base adjustments are already reflected in cooked values.
                continue

            default:
                continue
            }
        }

        return ranges
    }
}

/// DWARF sections whose compilation units can be enumerated.
public enum DWARFSection: Sendable, Equatable, Hashable {
    case info
    case types

    var isInfoFlag: Dwarf_Bool {
        switch self {
        case .info:
            return 1
        case .types:
            return 0
        }
    }
}

private func withCStringArray<Result>(
    _ strings: [String],
    _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?, UInt32) -> Result
) -> Result {
    guard !strings.isEmpty else {
        return body(nil, 0)
    }

    var storage: [UnsafeMutablePointer<CChar>?] = []
    storage.reserveCapacity(strings.count)

    for string in strings {
        let duplicated = string.withCString { ptr in
            strdup(ptr)
        }
        guard let duplicated else {
            fatalError("Failed to duplicate string for libdwarf consumption.")
        }
        storage.append(duplicated)
    }

    defer {
        for pointer in storage {
            if let pointer {
                free(pointer)
            }
        }
    }

    return storage.withUnsafeBufferPointer { buffer in
        guard let baseAddress = buffer.baseAddress else {
            return body(nil, 0)
        }
        return body(
            UnsafeMutablePointer(mutating: baseAddress),
            UInt32(buffer.count)
        )
    }
}
