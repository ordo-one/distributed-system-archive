import DistributedABI

/// A collection of one’s own with contiguous storage, conformed in the wire form of an array
/// through the library’s public helpers alone, as the SDK or a plugin would conform one.
struct Batch<Element> {
    var elements: [Element]

    init(elements: [Element]) {
        self.elements = elements
    }
}
extension Batch: Equatable where Element: Equatable {
}
extension Batch: Sendable where Element: Sendable {
}
extension Batch: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: Element...) {
        self.init(elements: elements)
    }
}
extension Batch: RandomAccessCollection {
    var startIndex: Int { self.elements.startIndex }
    var endIndex: Int { self.elements.endIndex }

    subscript(position: Int) -> Element { self.elements[position] }
}
extension Batch: RangeReplaceableCollection {
    init() {
        self.init(elements: [])
    }

    mutating func replaceSubrange<Replacement>(
        _ range: Range<Int>,
        with replacement: Replacement
    ) where Replacement: Collection, Replacement.Element == Element {
        self.elements.replaceSubrange(range, with: replacement)
    }
}
extension Batch: Transferable where Element: Transferable {
    var transferSize: Int { self.elements.span.arrayTransferSize }

    /// Its elements lie in contiguous storage, so it writes them from a span of it, with one
    /// copy when their type states that it is stored as its transfer bytes.
    func transfer(into output: inout TransferWriter) {
        output.append(uleb128: self.elements.count)
        output.append(elements: self.elements.span)
    }
    /// It reads its elements into the storage an output span lends, with one copy when their
    /// type states that it is stored as its transfer bytes.
    init(transferring input: inout TransferReader) throws(TransferError) {
        let count: Int = try input.readCount(of: Element.self)
        var elements: [Element] = []
        try elements.append(addingCapacity: count) {
            (output: inout OutputSpan<Element>) throws(TransferError) in
            try input.readElements(count: count, into: &output)
        }
        self.init(elements: elements)
    }
}
