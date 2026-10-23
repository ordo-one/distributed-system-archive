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
    var transferSize: Int { get }                   // the exact number of bytes written
    func transfer(into output: inout OutputRawSpan)
    init(transferring input: inout TransferReader) throws(TransferError)
}
```

The transport asks a value for its `transferSize`, reserves exactly that many bytes, and calls `transfer(into:)` with an `OutputRawSpan` over them. To read it back, the transport hands `init(transferring:)` a `TransferReader` over the arguments of the call; each value consumes exactly the bytes it wrote, the next argument reads on from there, and the transport refuses the call unless the arguments consume their bytes exactly. A type whose values all have the same size states it in `fixedTransferSize`; a collection of such values sizes itself from its count alone and checks that each element reads exactly that many bytes.

A composite sums the sizes of its parts, writes them in order and reads them back in the same order. There is no second API for a part: `transferSize`, `transfer(into:)` and `init(transferring:)` are the whole of it.

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
    func transfer(into output: inout OutputRawSpan) {
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
| `Array`, `ArraySlice`, `Set` | a ULEB128 count, then the elements one after another |
| `Dictionary` | a ULEB128 count, then each key and its value, one after another |
| an enum with an integer raw value | its raw value; a raw value with no case is refused |

A set or a dictionary that repeats an element or a key is refused. Set and dictionary elements travel in iteration order, which differs between processes, so equal values need not produce equal bytes.


## Building and using the library

DistributedABI is built with library evolution as a binary framework, and every body on the hot path is `@inlinable`, so a client specializes `Array<Transaction>.transfer(into:)` and the reader in its own module. The library target enables the `Lifetimes` experimental feature and strict memory safety; its module interface guards every lifetime annotation, so clients build without either flag. The unsafe operations in the library are the memcpy inside `OutputRawSpan.append(bytes:)` and, in the string conformances, the view of a native string’s UTF-8 storage as a span for that copy, because the standard library lends that storage to inlinable code only as a pointer; no public declaration mentions an unsafe pointer. The deployment target is macOS 26 or iOS 26 because of the UTF-8 APIs the string conformances use, `UTF8Span`, `String.utf8Span` and `String.init(copying:)`, and because of `Array.span`, through which an array sizes elements of variable size; all four are new there, while `RawSpan` and `OutputRawSpan` back-deploy to earlier releases. Building the package takes Swift 6.3 or later, as its manifests state, for the `@inline(always)` attribute of SE-0496.


## Version 8 and earlier versions

Version 8 starts again from the model of version 5, where a value lent its bytes and the transport framed them, and takes from versions 6 and 7 what they got right: typed throws, one error type, guards against hostile lengths, the variable-length API (`append(prefixed:)` and `takePrefixed()`), and little-endian integers. It is compatible with neither on the wire nor in the API. `BufferEncodable`, `BufferDecodable`, their encoder and decoder, and the deprecated `Serializable` and `Deserializable` are gone, so every process that talks to another must move to version 8 together.
