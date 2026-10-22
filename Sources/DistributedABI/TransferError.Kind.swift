extension TransferError {
    @frozen public enum Kind: Sendable {
        /// Too few bytes: the first number was asked for, the second remained. An expectation of
        /// zero bytes is the end of input, refused because bytes remained. A value of fixed size
        /// that read more or fewer bytes than its type states reports that size, then the number
        /// it read.
        case expected(Int, encountered: Int)
        /// A count or length past the bytes remaining, or a malformed ULEB128 number (overlong,
        /// or over `Int.max`), which reports a count of -1.
        case count(Int, remaining: Int)
        /// A `Bool`, `Optional` or `Result` discriminant byte out of range, or an integer raw
        /// value with no case, as the unsigned number its bits form on the wire.
        case discriminant(UInt64)
        /// A `Set` element or `Dictionary` key that repeats an earlier one, at this position.
        case duplicate(Int)
        /// A conformer’s own error, carried unchanged.
        case payload(any Error)
    }
}
