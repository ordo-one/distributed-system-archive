/// The unsigned LEB128 numbers that frame lengths and counts: seven bits a byte, least
/// significant group first, the high bit set on every byte but the last.
public enum ULEB128 {}
extension ULEB128 {
    /// The number of bytes `value` takes: one up to 127, two up to 16,383.
    @inlinable public static func size(_ value: UInt) -> Int {
        let value: UInt = value | 1
        return (UInt.bitWidth - value.leadingZeroBitCount + 6) / 7
    }

    /// The number of bytes a count or a length takes, which is never negative.
    @inlinable public static func size(_ value: Int) -> Int {
        Self.size(UInt.init(value))
    }
}
