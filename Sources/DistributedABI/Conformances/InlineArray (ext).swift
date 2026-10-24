extension InlineArray: Transferable where Element: Transferable {
    /// An inline array travels as its elements one after another, each of which delimits
    /// itself, with no count in front of them, since the count is part of its type. An inline
    /// array of count 0 (`InlineArray<0, Element>`) writes one zero byte instead, since every
    /// value takes at least one, and any other byte in its place is a
    /// ``TransferError/Kind/discriminant(_:)`` error.
    ///
    /// The layout is a fixed size of one byte when the count is zero. Otherwise it is the count
    /// times the element’s size, when the element states a layout and the product fits in
    /// `Int`, so that a composite holding an inline array keeps a fixed size: copied as stored
    /// when the element is, since the inline array then is too, and one element at a time
    /// otherwise. In any other case it is nil.
    @inlinable public static var transferLayout: TransferLayout? {
        if  count == 0 {
            return .fixed(size: 1)
        }
        guard
        let layout: TransferLayout = Element.transferLayout else {
            return nil
        }
        let product: (partialValue: Int, overflow: Bool) = count
            .multipliedReportingOverflow(by: layout.size)
        if  product.overflow {
            return nil
        }
        if  case .bitwise = layout {
            return .bitwise(size: product.partialValue)
        } else {
            return .fixed(size: product.partialValue)
        }
    }
    @inlinable public var transferSize: Int {
        if  let size: Int = Self.transferLayout?.size {
            return size
        }
        var size: Int = 0
        for i: Int in self.indices {
            size += self[i].transferSize
        }
        return size
    }

    /// Elements whose layout copies them as stored are written with one copy of their storage,
    /// and others one at a time.
    @inlinable public func transfer(into output: inout TransferWriter) {
        if  count == 0 {
            output.append(0)
            return
        }
        if  case _? = Element.bitwiseTransfer {
            output.append(bitwise: self.span)
            return
        }
        for i: Int in self.indices {
            output.append(element: self[i])
        }
    }
    /// Reads elements stored as their transfer bytes with one copy, through
    /// ``TransferReader/takeElements(_:into:)``, and others each through
    /// ``TransferReader/takeElement(_:)``, so that an element of fixed size must read exactly
    /// that many bytes.
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        if  count == 0 {
            switch try input.take(UInt8.self) {
            case 0: break
            case let code: throw .init(.discriminant(.init(code)))
            }
        } else if case _? = Element.bitwiseTransfer {
            self = try .init { (output: inout OutputSpan<Element>) throws(TransferError) in
                try input.takeElements(count, into: &output)
            }
            return
        }
        self = try .init { (_: Int) throws(TransferError) -> Element in
            try input.takeElement(Element.self)
        }
    }
}
