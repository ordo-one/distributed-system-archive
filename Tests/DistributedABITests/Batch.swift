import DistributedABI

/// A range-replaceable collection of one’s own, conformed in the wire form of an array through
/// the library’s public helpers alone, as the SDK or a plugin would conform one.
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
    var transferSize: Int { self.elements.span.elementsTransferSize }

    func transfer(into output: inout TransferWriter) {
        output.append(uleb128: UInt.init(self.elements.count))
        for element: Element in self.elements {
            element.transfer(into: &output)
        }
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        try self.init(transferringElements: &input)
    }
}
