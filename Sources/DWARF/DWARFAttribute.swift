import CLibdwarf

/// Represents the decoded value of a DWARF attribute.
public enum DWARFAttributeValue: Sendable, Equatable {
    case string(String)
    case address(UInt64)
    case unsigned(UInt64)
    case signed(Int64)
    case flag(Bool)
    case reference(UInt64)
    case unsupported
}

/// A typed view over a `Dwarf_Attribute`.
public struct DWARFAttribute: Sendable, Equatable {
    public let code: UInt16
    public let form: UInt16
    public let value: DWARFAttributeValue

    var stringValue: String? {
        if case let .string(value) = value { return value }
        return nil
    }

    public var unsignedValue: UInt64? {
        if case let .unsigned(value) = value { return value }
        return nil
    }

    var addressValue: UInt64? {
        if case let .address(value) = value { return value }
        return nil
    }
}
