import Foundation

/// Controls how symbolication responds to libdwarf errors encountered while exploring inline frames.
public struct SymbolicationOptions: Sendable {
    /// Determines whether libdwarf errors stop symbolication or get recorded as issues.
    public enum ErrorPolicy: Sendable {
        /// Propagate the libdwarf error immediately.
        case strict
        /// Record the failure in ``DWARFSymbolicationIssue`` and continue.
        case lenient
    }

    /// Whether traversal stops on the first libdwarf error or records it as an issue.
    public var errorPolicy: ErrorPolicy

    public init(errorPolicy: ErrorPolicy = .lenient) {
        self.errorPolicy = errorPolicy
    }
}

/// Captures non-fatal libdwarf failures recorded during symbolication.
public struct DWARFSymbolicationIssue: Sendable, CustomStringConvertible, Equatable {
    public let address: UInt64
    public let context: String
    public let message: String

    public init(address: UInt64, context: String, error: Error) {
        self.address = address
        self.context = context
        self.message = String(describing: error)
    }

    public var description: String {
        "\(context): \(message)"
    }
}
