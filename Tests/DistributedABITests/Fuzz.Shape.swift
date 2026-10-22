extension Fuzz {
    /// The layout of a wire form, as far as putting it in canonical order needs it.
    indirect enum Shape: Sendable {
        /// A value of fixed size, packed in place.
        case fixed(Int)
        /// A value of variable size with no parts to order: every byte its container framed
        /// for it.
        case opaque
        /// A discriminant byte, then the payload of that case, if it has one.
        case cases([Shape?])
        /// A ULEB128 count, then the elements, each behind its ULEB128 length unless it has a
        /// fixed size; in an order that carries no meaning unless `ordered`.
        case elements(Shape, ordered: Bool)
        /// A ULEB128 count, then each key followed by its value, framed as elements are, in an
        /// order that carries no meaning.
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
            output += input
            input = []
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
                guard
                let part: [UInt8] = element.framed(&input) else {
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
                guard
                let key: [UInt8] = key.framed(&input),
                let value: [UInt8] = value.framed(&input) else {
                    return false
                }
                parts.append(key + value)
            }
            parts.sort { $0.lexicographicallyPrecedes($1) }
            output += parts.joined()
            return true
        }
    }

    /// One part of a container, in place when it has a fixed size and behind its ULEB128
    /// length otherwise, in canonical order.
    private func framed(_ input: inout ArraySlice<UInt8>) -> [UInt8]? {
        var part: [UInt8] = []
        if  case .fixed = self {
            return self.canonical(&input, into: &part) ? part : nil
        }
        guard
        let length: Int = Self.uleb128(&input, into: &part), length <= input.count else {
            return nil
        }
        var inner: ArraySlice<UInt8> = input.prefix(length)
        input.removeFirst(length)
        guard self.canonical(&inner, into: &part), inner.isEmpty else {
            return nil
        }
        return part
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
