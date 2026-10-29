extension Fuzz {
    /// The layout of a wire form, as far as putting it in canonical order needs it.
    indirect enum Shape: Sendable {
        /// A value of fixed size, packed in place.
        case fixed(Int)
        /// A value of variable size with no parts to order: a ULEB128 length, then that many
        /// bytes.
        case opaque
        /// A discriminant byte, then the payload of that case, if it has one.
        case cases([Shape?])
        /// A ULEB128 count, then the elements one after another; in an order that carries no
        /// meaning unless `ordered`.
        case elements(Shape, ordered: Bool)
        /// A ULEB128 count, then each key followed by its value, in an order that carries no
        /// meaning.
        case entries(Shape, Shape)
    }
}
extension Fuzz.Shape {
    /// The bytes of one value of this shape with the elements of every unordered collection
    /// sorted by their bytes, and every other byte as it is; nil if the bytes do not have
    /// this shape.
    func canonical(_ bytes: [UInt8]) -> [UInt8]? {
        var input: ArraySlice<UInt8> = bytes[...]
        var output: [UInt8] = []
        guard self.canonical(&input, into: &output), input.isEmpty else {
            return nil
        }
        return output
    }

    private func canonical(
        _ input: inout ArraySlice<UInt8>,
        into output: inout [UInt8]
    ) -> Bool {
        switch self {
        case .fixed(let size):
            guard size <= input.count else {
                return false
            }
            output += input.prefix(size)
            input.removeFirst(size)
            return true

        case .opaque:
            guard
            let length: Int = Self.uleb128(&input, into: &output), length <= input.count else {
                return false
            }
            output += input.prefix(length)
            input.removeFirst(length)
            return true

        case .cases(let payloads):
            guard
            let discriminant: UInt8 = input.popFirst(), payloads.count > discriminant else {
                return false
            }
            output.append(discriminant)
            return payloads[Int.init(discriminant)]?.canonical(&input, into: &output) ?? true

        case .elements(let element, ordered: let ordered):
            guard
            let count: Int = Self.uleb128(&input, into: &output) else {
                return false
            }
            var parts: [[UInt8]] = []
            for _: Int in 0 ..< count {
                var part: [UInt8] = []
                guard element.canonical(&input, into: &part) else {
                    return false
                }
                parts.append(part)
            }
            if !ordered {
                parts.sort { $0.lexicographicallyPrecedes($1) }
            }
            output += parts.joined()
            return true

        case .entries(let key, let value):
            guard
            let count: Int = Self.uleb128(&input, into: &output) else {
                return false
            }
            var parts: [[UInt8]] = []
            for _: Int in 0 ..< count {
                var part: [UInt8] = []
                guard key.canonical(&input, into: &part), value.canonical(
                    &input,
                    into: &part
                ) else {
                    return false
                }
                parts.append(part)
            }
            parts.sort { $0.lexicographicallyPrecedes($1) }
            output += parts.joined()
            return true
        }
    }

    /// A ULEB128 number, copied to `output` exactly as it was written, so that a number in a
    /// form the library would not write still differs from the one it does write.
    private static func uleb128(
        _ input: inout ArraySlice<UInt8>,
        into output: inout [UInt8]
    ) -> Int? {
        var value: Int = 0
        var shift: Int = 0
        while let byte: UInt8 = input.popFirst(), shift < 63 {
            output.append(byte)
            value |= Int.init(byte & 0x7f) << shift
            if  byte < 0x80 {
                return value
            }
            shift += 7
        }
        return nil
    }
}
