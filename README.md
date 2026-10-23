# DistributedABI

DistributedABI is the wire format of Ordo’s distributed calls: how an argument or a result becomes bytes in a network frame, and how those bytes become a value again on the other side. Version 8 is built on one idea. The transport moves a value’s bytes; it does not rebuild them.


## A value lends its bytes, and delimits itself

Most of what crosses the wire already is its wire form. A message from the SBE SDK is a run of bytes laid out exactly as it is stored and sent, and an identifier is eight bytes. Such a value conforms to `ContiguousTransferable`: it lends its bytes for the duration of a closure, and it opens from a copy of bytes it is handed. Sending it costs one memcpy into the frame the transport allocated, and receiving it costs the one copy the value makes to own its bytes. Nothing is parsed or built on the way.

A value that does serialize (an integer, a string, an optional, a collection) conforms to `Transferable` and writes itself straight into the frame. The library owns no buffer of its own, so there is no intermediate array and no second copy. A native string is copied from its own UTF-8 storage; a string bridged from an `NSString` whose storage is not UTF-8 is transcoded on the way, which may allocate.

Every value delimits itself on the wire. A leaf whose size varies (a string, a serialized message) writes a ULEB128 length in front of its bytes; a collection writes a count in front of its elements; an optional writes a discriminant byte. A container or a composite therefore writes its parts one after another and reads them back in the same order, with no length of its own around any of them. A ULEB128 number takes one byte up to 127 and two up to 16,383, so a typical message pays one or two bytes of framing, and the transport, which once wrote that length itself, writes nothing in front of an argument.


## What a conformer implements

```swift
public protocol Transferable: Sendable {
    static var fixedTransferSize: Int? { get }      // nil unless every value has one size
    static var isBitwiseTransferable: Bool { get }  // false unless a value is stored as its bytes
    static var bitwiseDiscriminantCount: Int? { get } // nil unless stored as one byte, a case index
    var transferSize: Int { get }                   // the exact number of bytes written
    func transfer(into output: inout TransferWriter)
    init(transferring input: inout TransferReader) throws(TransferError)
}
```

The transport asks a value for its `transferSize`, reserves exactly that many bytes, and calls `transfer(into:)` with a `TransferWriter` over them: one call, `withTransferWriter`, lends the frame’s `OutputRawSpan` to the writer and takes it back with every byte written. The writer is the counterpart of `TransferReader`, and carries the library’s wire helpers, `append(_:)` for one byte, `append(bytes:)`, `append(uleb128:)`, `append(prefixed:)`, `append(littleEndian:)` and `append(element:)` for the element of a collection, so that they stay off the standard library’s `OutputRawSpan`. To read it back, the transport hands `init(transferring:)` a `TransferReader` over the arguments of the call; each value consumes exactly the bytes it wrote, the next argument reads on from there, and the transport refuses the call unless the arguments consume their bytes exactly. A type whose values all have the same size states it in `fixedTransferSize`; a collection of such values sizes itself from its count alone and checks that each element reads exactly that many bytes.

A composite sums the sizes of its parts, writes them in order and reads them back in the same order. There is no second API for a part: `transferSize`, `transfer(into:)` and `init(transferring:)` are the whole of it. Every value takes at least one byte on the wire, because a collection refuses a count of elements that the bytes remaining could not hold at one byte each before it reserves anything; a composite with no fields writes a byte of its own, a version or a zero, and reads it back. A debug build checks the rule wherever a collection writes an element.

```swift
struct Quote: Transferable {
    let instrument: UInt64
    let venue: String?
    let levels: [Int64]

    var transferSize: Int {
        self.instrument.transferSize
            + self.venue.transferSize
            + self.levels.transferSize
    }
    func transfer(into output: inout TransferWriter) {
        self.instrument.transfer(into: &output)
        self.venue.transfer(into: &output)
        self.levels.transfer(into: &output)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.instrument = try .init(transferring: &input)
        self.venue = try .init(transferring: &input)
        self.levels = try .init(transferring: &input)
    }
}
```

Nothing around a part marks where it ends, so a composite must read exactly the parts it wrote, in the same order. A part read short or long shifts every value after it, and the error, when one comes, is reported where the shifted bytes first fail to parse rather than at that part. The library’s own conformances read exactly what they write, and a collection still checks that an element of fixed size reads exactly that size; a hand-written composite needs a round-trip test that reads it back with a second copy of its bytes behind it, so that a read which stops early or runs on shows.

The reader is a borrowed cursor. It is `~Escapable`, so neither the reader nor the spans it hands out can outlive the buffer they read, and the compiler refuses code that tries; a value that keeps bytes copies them. Running out of bytes, meeting a malformed number, or finding a discriminant out of range throws a `TransferError` instead of trapping, and a count or length that the bytes remaining could not hold is refused before anything is reserved: every element takes at least one byte on the wire, and its fixed size when its type has one. That bounds the number of elements a reader reserves room for, not the memory they take once decoded, which for strings and collections can exceed their bytes on the wire.


## How a contiguous type gets its defaults

`ContiguousTransferable` refines `Transferable` with two requirements of its own:

```swift
public protocol ContiguousTransferable: Transferable {
    func withTransferBytes<Result>(_ body: (RawSpan) throws -> Result) rethrows -> Result
    init(transferBytes: RawSpan) throws(TransferError)
}
```

From those two, the protocol supplies all three requirements of `Transferable`: `transferSize` is the byte count of the lent span and of the ULEB128 length that precedes it, `transfer(into:)` is that length and one memcpy, and `init(transferring:)` reads the length and opens the value over that many bytes; a type that states a fixed size writes and reads its bytes alone. A message type of the SDK needs nothing more than a bridge from its own span API:

```swift
extension ContiguousTransferable where Self: SerializedSpanDecodable {
    public func withTransferBytes<Result>(_ body: (RawSpan) throws -> Result) rethrows -> Result {
        try self.withSerializedSpan(body)
    }
    public init(transferBytes: RawSpan) throws(TransferError) {
        do {
            try self.init(fromSerializedSpan: transferBytes)
        } catch {
            throw .payload(error)
        }
    }
}
extension Transaction: @retroactive ContiguousTransferable {}
```

The `payload` kind carries the type’s own error unchanged, which is how the transport tells a refused row from damaged bytes.


## The standard conformances

| Type | Wire form |
| --- | --- |
| The standard integers, `Int8` to `UInt128` | its bytes, little-endian, fixed size |
| `Bool` | one byte, 0 or 1 |
| `Float`, `Double` | the bit pattern, little-endian, fixed size |
| `String`, `Substring` | a ULEB128 length, then the UTF-8 bytes as they are, with no terminator; invalid UTF-8 is refused |
| `Optional` | one byte, 0 for `nil` and 1 for a value, then the value |
| `Result` | one byte, 0 for success and 1 for failure, then the payload |
| `Array`, `ArraySlice`, `ContiguousArray`, `Set` | a ULEB128 count, then the elements one after another |
| `InlineArray` | the elements one after another, with no count; one zero byte when it has none |
| `Dictionary` | a ULEB128 count, then each key and its value, one after another |
| an enum with an integer raw value | its raw value; a raw value with no case is refused |

A set or a dictionary that repeats an element or a key is refused. Set and dictionary elements travel in iteration order, which differs between processes, so equal values need not produce equal bytes.

An array, a contiguous array, a slice or an inline array whose elements are stored in memory exactly as their transfer bytes writes and reads their storage with one copy, with the bytes on the wire unchanged. An element type states this in `isBitwiseTransferable`, which is false by default. The fixed-width integers state it on a little-endian host, and `Float` and `Double`, which travel as their bit pattern; an enumeration with an integer raw value does not, since it is stored as its case index and not every byte is a case, and neither does `Bool`. A type that wraps one of them as its only stored property states it in one line, forwarding the wrapped type’s answer:

```swift
extension TransactionIdentifier: Transferable {
    @inlinable public static var isBitwiseTransferable: Bool { RawValue.isBitwiseTransferable }
}
```

`Bool`, and an enumeration with no payload, 2 to 256 cases and `UInt8` raw values that are exactly its case indices (0, 1, 2 and on in declaration order, as implicit raw values are), are stored as the one byte they travel as, since Swift lays out such an enumeration as its case index in one byte, but not every byte is a value. Such a type states its number of discriminants in `bitwiseDiscriminantCount` instead, `Bool` 2, and an array of them is read with one copy, each byte checked against that number where it lies first; a byte at or above it is refused with the error a read of one element at a time reports for it, the reader left just past it as that read leaves it. The statement is not meant to be written by hand: the SDK’s generator emits it for the enumerations it generates, and ordo-sdk’s derive macro for a plugin’s own, each after checking from the declaration that the raw values are implicit or exactly the case indices and counting the cases. A statement written by hand must guarantee the same, and nothing reports one that is wrong: a byte is refused only from the stated count up, so a count above the number of cases accepts a byte of no case as a value, and a count or raw values that do not match the cases read a byte as the wrong case, silently.

A composite states it from its fields’ own statements and its layout, every field at the offset the fields before it end at and no byte beyond them, which a derive macro can write as code that the optimizer folds to a constant. The collection checks the rest itself: the element’s fixed size must be the size and the stride of its memory, and its memory must be trivial to copy and destroy, which excludes strong, weak and unowned references, or each element travels one at a time through its own conformance. An `unowned(unsafe)` reference, an `Unmanaged` one or a raw pointer is plain bits to that check, so a type that states `isBitwiseTransferable` must hold none of them; the library cannot check it.

An inline array writes no count, because its count is part of its type. An inline array of count 0 (`InlineArray<0, Element>`) still takes the one byte every value must, a zero, and any other byte in its place is refused. Its fixed size is therefore one byte when the count is zero. Otherwise it is the count times its element’s fixed size, when the element states one and the product fits in `Int`, so a composite that holds an inline array keeps a fixed size of its own. In any other case it has none.

A collection of one’s own can travel exactly as an array or a dictionary does through the helpers the standard conformances use. `Span.arrayTransferSize` sizes elements in an array’s wire form, count included. The collection writes its count with `TransferWriter.append(uleb128:)`, then each element, or each key and its value, with `append(element:)`, which in a debug build checks that the element wrote at least one byte. A range-replaceable collection reads itself as an array with `init(transferringElements:)`, and any other collection reads its count with `TransferReader.takeCount(of:)`, or a keyed one with `takeCount(keys:values:)`, which refuses, before anything is reserved, a count the bytes remaining could not hold, and then reads each element, or each key and its value, with `takeElement(_:)`, which holds an element of fixed size to exactly that many bytes. A collection whose elements lie in contiguous storage writes them, after its count, with `append(elements:)` from a span of that storage, and reads them, after its count, with `takeElements(_:into:)` into the storage it initializes through an `OutputSpan`: both copy the elements’ storage at once when the element type states it is stored as its transfer bytes, with the same checks the standard conformances make, and otherwise go one element at a time. A keyed collection that keeps its keys and values apart has no such run of storage, and reads and writes each entry.


## Building and using the library

DistributedABI is built with library evolution as a binary framework, and every body on the hot path is `@inlinable`, so a client specializes `Array<Transaction>.transfer(into:)` and the reader in its own module. The library target enables the `Lifetimes` experimental feature and strict memory safety; its module interface guards every lifetime annotation, so clients build without either flag. The unsafe operations in the library are the memcpy inside `TransferWriter.append(bytes:)`; in the string conformances, the view of a native string’s UTF-8 storage as a span for that copy, because the standard library lends that storage to inlinable code only as a pointer; and, for a collection whose element type states it is stored as its transfer bytes, the view of the elements’ typed storage as bytes for that copy when it is written, and the copy of the bytes read into uninitialized typed storage, through `Array.init(unsafeUninitializedCapacity:initializingWith:)` and the buffer of an output span, when it is read, each behind the checks of size, stride and trivial copying and, for a number of discriminants, of every byte; no public declaration mentions an unsafe pointer. The deployment target is macOS 26 or iOS 26 because of the UTF-8 APIs the string conformances use, `UTF8Span`, `String.utf8Span` and `String.init(copying:)`, because of `Array.span`, through which an array sizes elements of variable size, and because of `InlineArray`; all five are new there, while `RawSpan` and `OutputRawSpan` back-deploy to earlier releases. Building the package takes Swift 6.3 or later, as its manifests state, for the `@inline(always)` attribute of SE-0496.


## Version 8 and earlier versions

Version 8 starts again from the model of version 5, where a value lent its bytes and the transport framed them, and takes from versions 6 and 7 what they got right: typed throws, one error type, guards against hostile lengths, the variable-length API (`append(prefixed:)` and `takePrefixed()`), and little-endian integers. It is compatible with neither on the wire nor in the API. `BufferEncodable`, `BufferDecodable`, their encoder and decoder, and the deprecated `Serializable` and `Deserializable` are gone, so every process that talks to another must move to version 8 together.
