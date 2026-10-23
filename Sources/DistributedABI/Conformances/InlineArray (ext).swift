extension InlineArray: Transferable where Element: Transferable {
    /// An inline array travels as its elements one after another, each of which delimits
    /// itself, with no count in front of them, since the count is part of its type. An inline
    /// array of count 0 (`InlineArray<0, Element>`) writes one zero byte instead, since every
    /// value takes at least one, and any other byte in its place is a
    /// ``TransferError/Kind/discriminant(_:)`` error.
    ///
    /// The fixed size is one byte when the count is zero. Otherwise it is the count times the
    /// element’s fixed size, when the element states one and the product fits in `Int`, so
    /// that a composite holding an inline array keeps a fixed size. In any other case it is
    /// nil.
    @inlinable public static var fixedTransferSize: Int? {
        if  count == 0 {
            return 1
        }
        guard
        let size: Int = Element.fixedTransferSize else {
            return nil
        }
        let product: (partialValue: Int, overflow: Bool) = count
            .multipliedReportingOverflow(by: size)
        return product.overflow ? nil : product.partialValue
    }
    @inlinable public var transferSize: Int {
        if  let size: Int = Self.fixedTransferSize {
            return size
        }
        var size: Int = 0
        for i: Int in self.indices {
            size += self[i].transferSize
        }
        return size
    }

    @inlinable public func transfer(into output: inout TransferWriter) {
        if  count == 0 {
            output.append(0)
            return
        }
        for i: Int in self.indices {
            output.append(element: self[i])
        }
    }
    /// Reads each element through ``TransferReader/takeElement(_:)``, so that an element of
    /// fixed size must read exactly that many bytes.
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        if  count == 0 {
            switch try input.take(UInt8.self) {
            case 0: break
            case let code: throw .init(.discriminant(.init(code)))
            }
        }
        self = try .init { (_: Int) throws(TransferError) -> Element in
            try input.takeElement(Element.self)
        }
    }
}
