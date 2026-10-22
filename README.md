# DistributedABI

DistributedABI is the wire format of Ordo’s distributed calls: how an argument or a result becomes bytes in a network frame, and how those bytes become a value again on the other side. Version 8 is built on one idea. The transport moves a value’s bytes; it does not rebuild them.


## A value lends its bytes, the container frames them

Most of what crosses the wire already is its wire form. A message from the SBE SDK is a run of bytes laid out exactly as it is stored and sent, and an identifier is eight bytes. Such a value conforms to `ContiguousTransferable`: it lends its bytes for the duration of a closure, and it opens from a copy of bytes it is handed. Sending it costs one memcpy into the frame the transport allocated, and receiving it costs the one copy the value makes to own its bytes. Nothing is parsed or built on the way.

A value that does serialize (an integer, a string, an optional, a collection) conforms to `Transferable` and writes itself straight into the frame. The library owns no buffer of its own, so there is no intermediate array and no second copy. A native string is copied from its own UTF-8 storage; a string bridged from an `NSString` whose storage is not UTF-8 is transcoded on the way, which may allocate.

No value records its own length. The **container** that holds it does: the transport writes a ULEB128 length in front of every argument, a collection writes a count in front of its elements and a length in front of each element whose size varies, and a composite does the same for its fields. A ULEB128 number takes one byte up to 127 and two up to 16,383, so a typical message pays one or two bytes of framing.


## What a conformer implements

```swift
public protocol Transferable: Sendable {
    static var fixedTransferSize: Int? { get }      // nil unless every value has one size
    var transferSize: Int { get }                   // the exact number of bytes written
    func transfer(into output: inout OutputRawSpan)
    init(transferring input: inout TransferReader) throws(TransferError)
}
```

The transport asks a value for its `transferSize`, reserves exactly that many bytes, and calls `transfer(into:)` with an `OutputRawSpan` over them. To read it back, the transport hands `init(transferring:)` a `TransferReader` over the bytes it framed for that value. A type whose values all have the same size states it in `fixedTransferSize`, and a collection of such values packs them with no lengths in between; such a type must then read exactly that many bytes.

A composite writes its parts in order. `append(framed:)` and `take(framed:)` apply the container’s rule to one part: a part whose type has a fixed size goes in as it is, any other behind its ULEB128 length.

```swift
struct Quote: Transferable {
    let instrument: UInt64
    let venue: String?
    let levels: [Int64]

    var transferSize: Int {
        self.instrument.framedTransferSize
            + self.venue.framedTransferSize
            + self.levels.framedTransferSize
    }
    func transfer(into output: inout OutputRawSpan) {
        output.append(framed: self.instrument)
        output.append(framed: self.venue)
        output.append(framed: self.levels)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.instrument = try input.take(framed: UInt64.self)
        self.venue = try input.take(framed: String?.self)
        self.levels = try input.take(framed: [Int64].self)
    }
}
```

The reader is a borrowed cursor. It is `~Escapable`, so neither the reader nor the spans it hands out can outlive the buffer they read, and the compiler refuses code that tries; a value that keeps bytes copies them. Running out of bytes, meeting a malformed number, or finding a discriminant out of range throws a `TransferError` instead of trapping, and a count is checked against the bytes present before anything is reserved, so hostile input cannot make a reader allocate more than it was sent.


## How a contiguous type gets its defaults

`ContiguousTransferable` refines `Transferable` with two requirements of its own:

```swift
public protocol ContiguousTransferable: Transferable {
    func withTransferBytes<Result>(_ body: (RawSpan) throws -> Result) rethrows -> Result
    init(transferBytes: RawSpan) throws(TransferError)
}
```

From those two, the protocol supplies all three requirements of `Transferable`: `transferSize` is the byte count of the lent span, `transfer(into:)` is one memcpy of it, and `init(transferring:)` opens the value over the bytes its container framed, or over exactly `fixedTransferSize` bytes when the type states a fixed size. A message type of the SDK needs nothing more than a bridge from its own span API:

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
| `String`, `Substring` | the UTF-8 bytes as they are, with no terminator; invalid UTF-8 is refused |
| `Optional` | one byte, 0 for `nil` and 1 for a value, then the value |
| `Result` | one byte, 0 for success and 1 for failure, then the payload |
| `Array`, `ArraySlice`, `Set` | a ULEB128 count, then the elements, packed or each behind its length |
| `Dictionary` | a ULEB128 count, then each key and its value, packed or each behind its length |
| an enum with an integer raw value | its raw value; a raw value with no case is refused |

A set or a dictionary that repeats an element or a key is refused. Set and dictionary elements travel in iteration order, which differs between processes, so equal values need not produce equal bytes.


## Building and using the library

DistributedABI is built with library evolution as a binary framework, and every body on the hot path is `@inlinable`, so a client specializes `Array<Transaction>.transfer(into:)` and the reader in its own module. The library target enables the `Lifetimes` experimental feature and strict memory safety; its module interface guards every lifetime annotation, so clients build without either flag. The unsafe operations in the library are the memcpy inside `OutputRawSpan.append(bytes:)` and, in the string conformances, the view of a native string’s UTF-8 storage as a span for that copy, because the standard library lends that storage to inlinable code only as a pointer; no public declaration mentions an unsafe pointer. Spans and `UTF8Span` need macOS 26 or iOS 26.


## Version 8 and earlier versions

Version 8 starts again from the model of version 5, where a value lent its bytes and the transport framed them, and takes from versions 6 and 7 what they got right: typed throws, one error type, guards against hostile lengths, the variable-length API (`append(prefixed:)` and `takePrefixed()`), and little-endian integers. It is compatible with neither on the wire nor in the API. `BufferEncodable`, `BufferDecodable`, their encoder and decoder, and the deprecated `Serializable` and `Deserializable` are gone, so every process that talks to another must move to version 8 together.
