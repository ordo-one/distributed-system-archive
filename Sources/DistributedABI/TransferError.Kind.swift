extension TransferError {
    /// What the input held that a read refused, or the conformer’s own error. Every case but
    /// two carries where the read stood, as the bytes remaining or a position, so that a
    /// refusal can be found in the frame; ``invalidDiscriminant(_:)`` carries the value read
    /// instead, and ``payload(_:)`` the conformer’s error as it is.
    @frozen public enum Kind: Sendable {
        /// Too few bytes: a read needed `needed` and `remaining` were left.
        case truncated(needed: Int, remaining: Int)
        /// Bytes after the last value: ``TransferReader/readEnd()`` found `remaining` unread.
        case trailingBytes(remaining: Int)
        /// A count of elements or a length in bytes that the `remaining` bytes cannot hold,
        /// refused before any room is reserved for it.
        case excessiveCount(Int, remaining: Int)
        /// A ULEB128 number not in canonical form, with `remaining` bytes left after it: one
        /// that runs past 64 bits, carries a redundant final zero byte, or exceeds `Int.max`,
        /// the largest count or length a reader can use.
        case malformedULEB128(remaining: Int)
        /// A `Bool`, `Optional` or `Result` discriminant byte out of range, a byte other than
        /// zero in place of an inline array of count 0 (`InlineArray<0, Element>`), or an
        /// integer raw value with no case, as the unsigned number its bits form on the wire:
        /// all of them for every standard integer, and the low 128 for a wider one.
        case invalidDiscriminant(UInt128)
        /// A `Set` element or `Dictionary` key that repeats an earlier one, at this position
        /// among the elements or entries.
        case duplicate(at: Int)
        /// A conformer’s own error, carried unchanged.
        case payload(any Error)
    }
}
