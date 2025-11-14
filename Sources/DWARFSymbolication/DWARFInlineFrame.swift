import Foundation

/// Represents a single frame in a call stack, which may be inlined.
public struct DWARFInlineFrame: Sendable, Equatable {
    /// The function name (demangled if possible).
    public let function: String
    /// The source file path.
    public let file: String
    /// The line number in the source file.
    public let line: UInt64
    /// The column number in the source file.
    public let column: UInt64
    /// Whether this frame was inlined at compile time.
    public let isInlined: Bool

    public init(
        function: String,
        file: String,
        line: UInt64,
        column: UInt64,
        isInlined: Bool
    ) {
        self.function = function
        self.file = file
        self.line = line
        self.column = column
        self.isInlined = isInlined
    }
}

/// Represents a symbolicated address with its full call stack (including inlined frames).
public struct DWARFSymbolicatedAddress: Sendable, Equatable {
    /// The address that was symbolicated.
    public let address: UInt64
    /// The call stack frames at this address, ordered from innermost (most specific) to outermost.
    /// Index 0 is the innermost frame (where the code is actually executing).
    /// The last frame is the outermost non-inlined function.
    public let frames: [DWARFInlineFrame]
    /// Issues encountered while computing the inline stack.
    public let issues: [DWARFSymbolicationIssue]

    public init(address: UInt64, frames: [DWARFInlineFrame], issues: [DWARFSymbolicationIssue] = []) {
        self.address = address
        self.frames = frames
        self.issues = issues
    }
}
