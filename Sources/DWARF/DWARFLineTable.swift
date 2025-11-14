import CLibdwarf

public struct DWARFLineTable: Sendable {
    private struct SequenceDescriptor: Sendable {
        let startIndex: Int
        let endIndex: Int
        let lowAddress: UInt64
        let highAddress: UInt64
    }

    public struct Row: Sendable {
        public let address: UInt64
        public let file: String
        public let fileIndex: UInt64?
        public let line: UInt64
        public let column: UInt64
        public let isStatement: Bool
        public let isEndSequence: Bool
        public let isActual: Bool
    }

    public let version: UInt64
    public let rows: [Row]
    public let filePaths: [UInt64: String]
    private let sequences: [SequenceDescriptor]

    public init(version: UInt64, rows: [Row], filePaths: [UInt64: String] = [:]) {
        self.version = version
        self.rows = rows
        self.filePaths = filePaths
        self.sequences = DWARFLineTable.buildSequences(from: rows)
    }

    /// Returns the line-table row with the greatest address less than or equal to `address`.
    public func row(containing address: UInt64) -> Row? {
        guard !rows.isEmpty else { return nil }

        for sequence in sequences {
            guard address >= sequence.lowAddress,
                  address <= sequence.highAddress else {
                continue
            }

            if let match = search(sequence: sequence, for: address) {
                return match
            }
        }
        return nil
    }

    /// Returns the best line-table row for `address`, if any.
    public func location(for address: UInt64) -> Row? {
        row(containing: address)
    }

    /// Returns the recorded file path for the supplied DWARF line-table file index.
    public func filePath(forFileIndex index: UInt64) -> String? {
        filePaths[index]
    }

    private func search(sequence: SequenceDescriptor, for address: UInt64) -> Row? {
        var low = sequence.startIndex
        var high = sequence.endIndex - 1
        var bestMatch: Row?

        while low <= high {
            let mid = (low + high) / 2
            let candidate = rows[mid]
            if candidate.address == address {
                return candidate
            } else if candidate.address < address {
                bestMatch = candidate
                low = mid + 1
            } else {
                if mid == sequence.startIndex { break }
                high = mid - 1
            }
        }
        return bestMatch
    }

    private static func buildSequences(from rows: [Row]) -> [SequenceDescriptor] {
        guard !rows.isEmpty else { return [] }
        var sequences: [SequenceDescriptor] = []

        var currentStart: Int?
        var currentLow: UInt64 = 0
        var currentHigh: UInt64 = 0

        func finalizeSequence(endingAt endIndex: Int) {
            guard let start = currentStart else { return }
            sequences.append(
                SequenceDescriptor(
                    startIndex: start,
                    endIndex: endIndex,
                    lowAddress: currentLow,
                    highAddress: currentHigh
                )
            )
            currentStart = nil
        }

        for (index, row) in rows.enumerated() {
            if currentStart == nil {
                currentStart = index
                currentLow = row.address
                currentHigh = row.address
            } else {
                if row.address > currentHigh {
                    currentHigh = row.address
                }
            }

            if row.isEndSequence {
                finalizeSequence(endingAt: index + 1)
            }
        }

        if currentStart != nil {
            finalizeSequence(endingAt: rows.count)
        }

        return sequences
    }
}
