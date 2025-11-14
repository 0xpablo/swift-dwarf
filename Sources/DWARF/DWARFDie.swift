import CLibdwarf

/// A Debug Information Entry (DIE) representing a program entity in DWARF.
///
/// DIEs are the building blocks of DWARF debug information, representing program
/// entities like functions, variables, types, and lexical scopes. They form a tree
/// structure where each DIE can have attributes, children, and siblings.
///
/// ## Overview
///
/// DIEs are obtained from compilation units and can be traversed to explore
/// the program structure:
///
/// ```swift
/// // Navigate the DIE tree
/// if let child = try die.firstChild() {
///     // Process child DIE
///     if let tag = try child.tag() {
///         switch tag {
///         case UInt16(DW_TAG_subprogram):
///             print("Found function: \(try child.name() ?? "anonymous")")
///         case UInt16(DW_TAG_variable):
///             print("Found variable: \(try child.name() ?? "anonymous")")
///         default:
///             break
///         }
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Navigating the DIE Tree
/// - ``firstChild()``
/// - ``sibling()``
/// - ``children()``
///
/// ### Accessing DIE Information
/// - ``attributes()``
/// - ``tag()``
/// - ``name()``
/// - ``offset()``
///
/// - Note: DIE objects maintain a weak reference to their owning session.
///         They become invalid when the session is closed.
public final class DWARFDie {
    private weak var session: DWARFSession?
    let raw: Dwarf_Die

    init(session: DWARFSession, raw: Dwarf_Die) {
        self.session = session
        self.raw = raw
    }

    deinit {
        if let session = session, !session.isClosed {
            dwarf_dealloc_die(raw)
        }
    }

    func owningSession() throws -> DWARFSession {
        try requireSession()
    }

    private func requireSession() throws -> DWARFSession {
        guard let session else { throw DWARFSession.StateError.closed }
        return session
    }

    /// Returns the first child DIE if one exists.
    public func firstChild() throws -> DWARFDie? {
        let session = try requireSession()
        var child: Dwarf_Die?
        var error: Dwarf_Error?
        let result = dwarf_child(raw, &child, &error)
        switch result {
        case DW_DLV_OK:
            guard let child else { return nil }
            return DWARFDie(session: session, raw: child)
        case DW_DLV_NO_ENTRY:
            return nil
        default:
            let handle = try session.borrowHandle()
            throw DWARFError.consume(debug: handle, error: error)
        }
    }

    /// Returns the next sibling DIE relative to this node, if any.
    public func sibling() throws -> DWARFDie? {
        let session = try requireSession()
        var siblingDie: Dwarf_Die?
        var error: Dwarf_Error?
        let result = dwarf_siblingof_c(raw, &siblingDie, &error)
        switch result {
        case DW_DLV_OK:
            guard let siblingDie else { return nil }
            return DWARFDie(session: session, raw: siblingDie)
        case DW_DLV_NO_ENTRY:
            return nil
        default:
            let handle = try session.borrowHandle()
            throw DWARFError.consume(debug: handle, error: error)
        }
    }

    /// Returns all attributes on this DIE decoded into Swift-friendly values.
    public func attributes() throws -> [DWARFAttribute] {
        let session = try requireSession()
        var listPointer: UnsafeMutablePointer<Dwarf_Attribute?>?
        var listLength: Dwarf_Signed = 0
        var error: Dwarf_Error?
        let result = dwarf_attrlist(raw, &listPointer, &listLength, &error)
        switch result {
        case DW_DLV_NO_ENTRY:
            return []
        case DW_DLV_ERROR:
            let handle = try session.borrowHandle()
            throw DWARFError.consume(debug: handle, error: error)
        default:
            break
        }

        guard let listPointer else { return [] }
        defer {
            session.deallocateAttributeList(listPointer)
        }

        var decoded: [DWARFAttribute] = []
        decoded.reserveCapacity(Int(listLength))
        for index in 0..<Int(listLength) {
            guard let attributePointer = listPointer[index] else { continue }
            if let attribute = try session.decodeAttribute(attributePointer) {
                decoded.append(attribute)
            }
        }
        return decoded
    }

    /// Returns the attribute with the specified code, if present.
    public func attribute(_ code: UInt16) throws -> DWARFAttribute? {
        let session = try requireSession()
        var attributePointer: Dwarf_Attribute?
        var error: Dwarf_Error?
        let result = dwarf_attr(raw, code, &attributePointer, &error)
        switch result {
        case DW_DLV_NO_ENTRY:
            return nil
        case DW_DLV_ERROR:
            let handle = try session.borrowHandle()
            throw DWARFError.consume(debug: handle, error: error)
        default:
            break
        }

        guard let attributePointer else { return nil }
        return try session.decodeAttribute(attributePointer)
    }

    /// Returns the DIE name (`DW_AT_name`) if present.
    public func name() throws -> String? {
        try attribute(UInt16(DW_AT_name))?.stringValue
    }

    /// Returns the linkage/mangled name (`DW_AT_linkage_name` or `DW_AT_MIPS_linkage_name`) if present.
    public func linkageName() throws -> String? {
        if let name = try attribute(UInt16(DW_AT_linkage_name))?.stringValue {
            return name
        }
        return try attribute(UInt16(DW_AT_MIPS_linkage_name))?.stringValue
    }

    /// Returns a human-readable display name for this DIE.
    /// Prefers `DW_AT_name` (unmangled) and falls back to linkage name when needed.
    public func displayName() throws -> String? {
        if let simple = try name(), !simple.isEmpty {
            return simple
        }
        return try linkageName()
    }

    /// Returns the DIE tag (DW_TAG_*).
    public func tag() throws -> UInt16 {
        let session = try requireSession()
        var tagValue: Dwarf_Half = 0
        var error: Dwarf_Error?
        let result = dwarf_tag(raw, &tagValue, &error)
        switch result {
        case DW_DLV_OK:
            return tagValue
        default:
            let handle = try session.borrowHandle()
            throw DWARFError.consume(debug: handle, error: error)
        }
    }

    /// Returns the lower bound PC if this DIE represents code.
    public func lowPC() throws -> UInt64? {
        guard let attribute = try attribute(UInt16(DW_AT_low_pc)) else {
            return nil
        }
        switch attribute.value {
        case .address(let value):
            return value
        case .unsigned(let value):
            return value
        default:
            return nil
        }
    }

    /// Returns the upper bound PC if this DIE represents code.
    public func highPC() throws -> UInt64? {
        guard let attribute = try attribute(UInt16(DW_AT_high_pc)) else {
            return nil
        }
        switch attribute.value {
        case .address(let value):
            return value
        case .unsigned(let offset):
            if let low = try lowPC() {
                return low &+ offset
            }
            return nil
        default:
            return nil
        }
    }

    /// Returns the set of address ranges covered by this DIE, if any.
    public func addressRanges() throws -> [Range<UInt64>] {
        let session = try requireSession()
        if let ranges = try session.fetchRanges(for: self) {
            return ranges
        }
        if let low = try lowPC(), let high = try highPC(), high > low {
            return [low..<high]
        }
        return []
    }

    /// Returns true if this DIE's address ranges contain the provided address.
    public func contains(address: UInt64) throws -> Bool {
        try addressRanges().contains(where: { $0.contains(address) })
    }

    /// Returns a sequence of the DIE's immediate children.
    public func children() -> Children {
        Children(parent: self)
    }

    /// Returns all immediate children whose DW_TAG matches `tag`.
    public func children(matchingTag tag: UInt16) throws -> [DWARFDie] {
        var matches: [DWARFDie] = []
        var iterator = children().makeIterator()
        while let child = iterator.next() {
            if let value = try? child.tag(), value == tag {
                matches.append(child)
            }
        }
        if let error = iterator.error {
            throw error
        }
        return matches
    }

    /// Follows a DW_AT_abstract_origin reference to get the original DIE.
    /// This is commonly used for inlined subroutines to reference their original function definition.
    public func abstractOrigin() throws -> DWARFDie? {
        let session = try requireSession()
        guard let attr = try attribute(UInt16(DW_AT_abstract_origin)) else {
            return nil
        }

        guard case .reference(let offset) = attr.value else {
            return nil
        }

        // Get the DIE at this offset
        var resultDie: Dwarf_Die?
        var error: Dwarf_Error?
        let handle = try session.borrowHandle()
        let result = dwarf_offdie_b(
            handle,
            Dwarf_Off(offset),
            1, // is_info (we're in .debug_info section)
            &resultDie,
            &error
        )

        switch result {
        case DW_DLV_OK:
            guard let resultDie else { return nil }
            return DWARFDie(session: session, raw: resultDie)
        case DW_DLV_NO_ENTRY:
            return nil
        default:
            throw DWARFError.consume(debug: handle, error: error)
        }
    }
}

extension DWARFDie {
    public struct Children: Sequence {
        public struct Iterator: IteratorProtocol {
            private var cursor: DWARFDie?
            public private(set) var error: Error?

            fileprivate init(parent: DWARFDie) {
                do {
                    cursor = try parent.firstChild()
                } catch {
                    cursor = nil
                    self.error = error
                }
            }

            public mutating func next() -> DWARFDie? {
                guard error == nil, let current = cursor else { return nil }
                do {
                    cursor = try current.sibling()
                } catch {
                    self.error = error
                    cursor = nil
                }
                return current
            }
        }

        private let parent: DWARFDie

        fileprivate init(parent: DWARFDie) {
            self.parent = parent
        }

        public func makeIterator() -> Iterator {
            Iterator(parent: parent)
        }
    }
}
