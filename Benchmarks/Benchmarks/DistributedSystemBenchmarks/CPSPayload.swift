import Benchmark
import DistributedABI
import Foundation

//  COMPUTED-PROPERTY LIVE VALUES: Codable/JSON (today) vs DistributedABI (#23 + #24).
//
//  The ordo computed-property live-value path (BestPrice / MarketData ticks) crosses the
//  distributed system as `[ComputedPropertyTable]` snapshots and `[ComputedPropertyTable.Update]`
//  deltas, pushed by `Distributor.handleUpdates` over `ComputedPropertiesServiceClientEndpoint`
//  (ordo PluginExecutor). The endpoint's `SerializationRequirement` is `Transferable`, but the
//  Transferable conformance is implemented with JSON TODAY:
//
//      ~/ordo .../PluginExecutor/ComputedProperties/ComputedProperties+Endpoint.swift:218-256
//      ComputedPropertyTable[.Update].withUnsafeBytesSerialization { JSONEncoder().encode(
//          CodableProperties(self.storage)) }   // [ComputedProperty.Key : PropertyValue]
//      // source comments: "TODO: tmp JSON based implementation", "should be table encoding"
//      // the custom Key/FieldUpdate Codable carry "to be removed after using proper encoding".
//
//  So #4 (computed properties) is JSON on the wire — the SAME shape as #1 (the quoter
//  plugin-to-plugin flow, QuoteTablePayload.swift). This file quantifies moving that ONE path to
//  the DistributedABI binary codec, exactly as QuoteTablePayload does for the quoter:
//    * baseline  — Foundation JSONEncoder/JSONDecoder (the real path). Numbers render as ASCII
//                  digits; property identifiers render as base62 strings; FieldUpdate/PropertyValue
//                  render as tagged objects.
//    * #23       — [UInt8]-backed BufferEncoder + ArraySlice BufferDecoder (encode = send copy;
//                  decode = a fresh [UInt8], the ByteBuffer -> Array receive copy).
//    * #24       — zero-copy SpanEncoder (writes straight into a reserved region, no staging /
//                  no send copy) + SpanDecoder (decodes from borrowed memory, no receive copy).
//
//  DUAL PURPOSE. Because cps live values type-erase to PropertyValue + identifier, these payloads
//  ARE SDK types (Price/Quantity = FixedPointDecimal -> Int64, Timestamp -> UInt64, identifiers ->
//  UInt64, Int8 enums) encoded via the Span surface. So the same numbers also stand in for "a
//  customer passes an SDK type across a plugin-to-plugin boundary": the conformance that makes #4
//  fast is the same conformance that makes SDK types first-class customer payloads out of the box.
//  Nothing here touches the FlatBuffers path the SDK uses internally for whole objects (#3).
//
//  NOT STORED. cps values are ephemeral live RPC, never persisted, so the positional/tagless
//  binary format needs no persistence/format-evolution capability — and adding a computed property
//  (even a customer one) does NOT change the wire, because the wire is identifier-keyed through a
//  fixed PropertyValue case set, not positional per-cps.
//
//  REPLICA SPEC (self-contained, NO SDK dependency). We model PropertyValue as a tagged enum over
//  the cases the MarketData family uses (price/quantity = Int64, timestamp = UInt64, integer = Int,
//  a 1-byte enumeration case, a variable-length text case, and an indirect `structure` case for the
//  recursive stress payload); FieldUpdate as a .replace/.remove tri-state; ComputedProperty.Key as
//  a UInt64 PropertyIdentifier (base62 string in JSON, UInt64 on the binary wire); the Update /
//  snapshot messages as id + ordered [key: value] entries; and a batch as [Update] (the throttled
//  NotificationBatch, Distributor.swift:123 ~20Hz over N instruments). Wire bytes are byte-identical
//  between #23 and #24 (asserted), and every payload round-trips through all three encoders.

// MARK: - Seeded PRNG (deterministic fixtures, built once)

/// SplitMix64 — deterministic so the fixtures are byte-identical across runs/worktrees and all
/// three serializers measure the SAME bytes. (Named CPS* to avoid clashing with the SplitMix64 /
/// QTSplitMix64 already defined in this benchmark module.)
struct CPSSplitMix64 {
    var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        self.state = self.state &+ 0x9E37_79B9_7F4A_7C15
        var z: UInt64 = self.state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - base62 identifier rendering (faithful JSON key shape)

//  ordo PropertyIdentifiers are 64-bit Frostflakes rendered as ~11-char base62 strings (the literal
//  ids in MarketData (cps).swift, e.g. bidPrice "JNp1Z2rZ4gE"). The JSON wire key-stringifies the
//  identifier; the binary wire writes the UInt64. base62 here models that key shape so JSON pays the
//  realistic string cost while #23/#24 pay 8 bytes. Round-trip is over the UInt64 raw value.

private let cpsBase62: [UInt8] = Array(
    "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8
)
func cpsBase62Encode(_ value: UInt64) -> String {
    if  value == 0 { return "0" }
    var v: UInt64 = value
    var bytes: [UInt8] = []
    while v > 0 {
        bytes.append(cpsBase62[Int(v % 62)])
        v /= 62
    }
    return String(decoding: bytes.reversed(), as: Unicode.UTF8.self)
}
func cpsBase62Decode(_ string: String) -> UInt64 {
    var v: UInt64 = 0
    for c: UInt8 in string.utf8 {
        let digit: UInt64
        switch c {
        case 0x30 ... 0x39: digit = UInt64(c - 0x30)          // 0-9 -> 0..9
        case 0x41 ... 0x5A: digit = UInt64(c - 0x41) + 10     // A-Z -> 10..35
        case 0x61 ... 0x7A: digit = UInt64(c - 0x61) + 36     // a-z -> 36..61
        default: digit = 0
        }
        v = v &* 62 &+ digit
    }
    return v
}

// MARK: - Replica model types (NO SDK dependency)

/// Model of `ComputedProperty.Key` / `PropertyIdentifier`. A UInt64 on the binary wire; a base62
/// string in JSON (matching the real key-stringified PropertyIdentifier).
struct PropertyID: Hashable {
    var raw: UInt64
}
extension PropertyID: Codable {
    init(from decoder: any Decoder) throws {
        let s: String = try decoder.singleValueContainer().decode(String.self)
        self.init(raw: cpsBase62Decode(s))
    }
    func encode(to encoder: any Encoder) throws {
        var c: any SingleValueEncodingContainer = encoder.singleValueContainer()
        try c.encode(cpsBase62Encode(self.raw))
    }
}
extension PropertyID: BufferEncodable {
    func encode(to output: inout BufferEncoder) {
        self.raw.encode(to: &output)
    }
}
extension PropertyID: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        .init(raw: try .decode(from: &input))
    }
}
extension PropertyID: SpanDecodable {
    static func decode(from input: inout SpanDecoder) throws(BufferDecodingError) -> Self {
        .init(raw: try .decode(from: &input))
    }
}

/// PropertyValue tag (RawRepresentable UInt8, so decode gets invalid-discriminant handling free).
enum PVTag: UInt8 {
    case price, quantity, timestamp, integer, enumeration, text, structure
}
extension PVTag: BufferDecodable, SpanDecodable {}

/// Model of `PropertyValue` — the type-erased value carried for every cps field. Cases cover the
/// MarketData family plus an indirect `structure` case for the recursive stress payload.
enum CPSValue: Equatable {
    case price(Int64)            // FixedPointDecimal -> Int64
    case quantity(Int64)         // FixedPointDecimal -> Int64
    case timestamp(UInt64)       // Timestamp nanoseconds
    case integer(Int)            // Int (e.g. numberOfTrades)
    case enumeration(UInt8)      // Int8-backed enum case (MarketPhase / AuctionImbalanceQuantitySide)
    case text(String)            // variable-length (e.g. FXRate.fxPath)
    indirect case structure([CPSValue])
}
extension CPSValue: BufferEncodable {
    func encode(to output: inout BufferEncoder) {
        switch self {
        case .price(let v):
            PVTag.price.rawValue.encode(to: &output)
            v.encode(to: &output)
        case .quantity(let v):
            PVTag.quantity.rawValue.encode(to: &output)
            v.encode(to: &output)
        case .timestamp(let v):
            PVTag.timestamp.rawValue.encode(to: &output)
            v.encode(to: &output)
        case .integer(let v):
            PVTag.integer.rawValue.encode(to: &output)
            v.encode(to: &output)
        case .enumeration(let v):
            PVTag.enumeration.rawValue.encode(to: &output)
            v.encode(to: &output)
        case .text(let v):
            PVTag.text.rawValue.encode(to: &output)
            v.encode(to: &output)
        case .structure(let values):
            PVTag.structure.rawValue.encode(to: &output)
            values.encode(to: &output)
        }
    }
}
extension CPSValue: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        let tag: PVTag = try .decode(from: &input)
        switch tag {
        case .price: return .price(try .decode(from: &input))
        case .quantity: return .quantity(try .decode(from: &input))
        case .timestamp: return .timestamp(try .decode(from: &input))
        case .integer: return .integer(try .decode(from: &input))
        case .enumeration: return .enumeration(try .decode(from: &input))
        case .text: return .text(try .decode(from: &input))
        case .structure: return .structure(try .decode(from: &input))
        }
    }
}
extension CPSValue: SpanDecodable {
    static func decode(from input: inout SpanDecoder) throws(BufferDecodingError) -> Self {
        let tag: PVTag = try .decode(from: &input)
        switch tag {
        case .price: return .price(try .decode(from: &input))
        case .quantity: return .quantity(try .decode(from: &input))
        case .timestamp: return .timestamp(try .decode(from: &input))
        case .integer: return .integer(try .decode(from: &input))
        case .enumeration: return .enumeration(try .decode(from: &input))
        case .text: return .text(try .decode(from: &input))
        case .structure: return .structure(try .decode(from: &input))
        }
    }
}
extension CPSValue: Codable {
    //  Synthesized-style Codable producing a tagged JSON object, representative of JSONEncoder over
    //  a boxed enum value. Single explicit coding so JSON and binary encode the SAME logical value.
    private enum CodingKeys: String, CodingKey { case tag, value, values }
    func encode(to encoder: any Encoder) throws {
        var c: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .price(let v):
            try c.encode(PVTag.price.rawValue, forKey: .tag)
            try c.encode(v, forKey: .value)
        case .quantity(let v):
            try c.encode(PVTag.quantity.rawValue, forKey: .tag)
            try c.encode(v, forKey: .value)
        case .timestamp(let v):
            try c.encode(PVTag.timestamp.rawValue, forKey: .tag)
            try c.encode(v, forKey: .value)
        case .integer(let v):
            try c.encode(PVTag.integer.rawValue, forKey: .tag)
            try c.encode(v, forKey: .value)
        case .enumeration(let v):
            try c.encode(PVTag.enumeration.rawValue, forKey: .tag)
            try c.encode(v, forKey: .value)
        case .text(let v):
            try c.encode(PVTag.text.rawValue, forKey: .tag)
            try c.encode(v, forKey: .value)
        case .structure(let values):
            try c.encode(PVTag.structure.rawValue, forKey: .tag)
            try c.encode(values, forKey: .values)
        }
    }
    init(from decoder: any Decoder) throws {
        let c: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        let raw: UInt8 = try c.decode(UInt8.self, forKey: .tag)
        guard let tag: PVTag = .init(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .tag, in: c, debugDescription: "bad tag")
        }
        switch tag {
        case .price: self = .price(try c.decode(Int64.self, forKey: .value))
        case .quantity: self = .quantity(try c.decode(Int64.self, forKey: .value))
        case .timestamp: self = .timestamp(try c.decode(UInt64.self, forKey: .value))
        case .integer: self = .integer(try c.decode(Int.self, forKey: .value))
        case .enumeration: self = .enumeration(try c.decode(UInt8.self, forKey: .value))
        case .text: self = .text(try c.decode(String.self, forKey: .value))
        case .structure: self = .structure(try c.decode([CPSValue].self, forKey: .values))
        }
    }
}

/// FieldUpdate tag (RawRepresentable UInt8).
enum FUTag: UInt8 {
    case replace, remove
}
extension FUTag: BufferDecodable, SpanDecodable {}

/// Model of `FieldUpdate<PropertyValue>` — the per-field tri-state in an Update (combined with the
/// fact that only present fields are materialized, this gives absent / replace / clear).
enum FieldUpdateLike: Equatable {
    case replace(CPSValue)
    case remove
}
extension FieldUpdateLike: BufferEncodable {
    func encode(to output: inout BufferEncoder) {
        switch self {
        case .replace(let v):
            FUTag.replace.rawValue.encode(to: &output)
            v.encode(to: &output)
        case .remove:
            FUTag.remove.rawValue.encode(to: &output)
        }
    }
}
extension FieldUpdateLike: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        let tag: FUTag = try .decode(from: &input)
        switch tag {
        case .replace: return .replace(try .decode(from: &input))
        case .remove: return .remove
        }
    }
}
extension FieldUpdateLike: SpanDecodable {
    static func decode(from input: inout SpanDecoder) throws(BufferDecodingError) -> Self {
        let tag: FUTag = try .decode(from: &input)
        switch tag {
        case .replace: return .replace(try .decode(from: &input))
        case .remove: return .remove
        }
    }
}
extension FieldUpdateLike: Codable {
    private enum CodingKeys: String, CodingKey { case tag, value }
    func encode(to encoder: any Encoder) throws {
        var c: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .replace(let v):
            try c.encode(FUTag.replace.rawValue, forKey: .tag)
            try c.encode(v, forKey: .value)
        case .remove:
            try c.encode(FUTag.remove.rawValue, forKey: .tag)
        }
    }
    init(from decoder: any Decoder) throws {
        let c: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        let raw: UInt8 = try c.decode(UInt8.self, forKey: .tag)
        guard let tag: FUTag = .init(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .tag, in: c, debugDescription: "bad tag")
        }
        switch tag {
        case .replace: self = .replace(try c.decode(CPSValue.self, forKey: .value))
        case .remove: self = .remove
        }
    }
}

/// One entry of an Update: a property key + its FieldUpdate. Models `[ComputedProperty.Key:
/// FieldUpdate<PropertyValue>]` as an ordered list (deterministic; the dictionary's entries).
struct CPSUpdateEntry: Equatable, Codable {
    var key: PropertyID
    var value: FieldUpdateLike
}
extension CPSUpdateEntry: BufferEncodable {
    func encode(to output: inout BufferEncoder) {
        self.key.encode(to: &output)
        self.value.encode(to: &output)
    }
}
extension CPSUpdateEntry: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        let key: PropertyID = try .decode(from: &input)
        let value: FieldUpdateLike = try .decode(from: &input)
        return .init(key: key, value: value)
    }
}
extension CPSUpdateEntry: SpanDecodable {
    static func decode(from input: inout SpanDecoder) throws(BufferDecodingError) -> Self {
        let key: PropertyID = try .decode(from: &input)
        let value: FieldUpdateLike = try .decode(from: &input)
        return .init(key: key, value: value)
    }
}

/// One entry of a snapshot: a property key + its PropertyValue. Models `[ComputedProperty.Key:
/// PropertyValue]`.
struct CPSSnapshotEntry: Equatable, Codable {
    var key: PropertyID
    var value: CPSValue
}
extension CPSSnapshotEntry: BufferEncodable {
    func encode(to output: inout BufferEncoder) {
        self.key.encode(to: &output)
        self.value.encode(to: &output)
    }
}
extension CPSSnapshotEntry: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        let key: PropertyID = try .decode(from: &input)
        let value: CPSValue = try .decode(from: &input)
        return .init(key: key, value: value)
    }
}
extension CPSSnapshotEntry: SpanDecodable {
    static func decode(from input: inout SpanDecoder) throws(BufferDecodingError) -> Self {
        let key: PropertyID = try .decode(from: &input)
        let value: CPSValue = try .decode(from: &input)
        return .init(key: key, value: value)
    }
}

/// Model of `ComputedPropertyTable.Update` (the delta) — object id + property updates.
struct CPSUpdate: Equatable, Codable {
    var id: UInt64                       // InstrumentIdentifier rawValue
    var properties: [CPSUpdateEntry]
}
extension CPSUpdate: BufferEncodable {
    func encode(to output: inout BufferEncoder) {
        self.id.encode(to: &output)
        self.properties.encode(to: &output)
    }
}
extension CPSUpdate: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        let id: UInt64 = try .decode(from: &input)
        let properties: [CPSUpdateEntry] = try .decode(from: &input)
        return .init(id: id, properties: properties)
    }
}
extension CPSUpdate: SpanDecodable {
    static func decode(from input: inout SpanDecoder) throws(BufferDecodingError) -> Self {
        let id: UInt64 = try .decode(from: &input)
        let properties: [CPSUpdateEntry] = try .decode(from: &input)
        return .init(id: id, properties: properties)
    }
}

/// Model of `ComputedPropertyTable` (the snapshot) — object id + property values.
struct CPSSnapshot: Equatable, Codable {
    var id: UInt64
    var properties: [CPSSnapshotEntry]
}
extension CPSSnapshot: BufferEncodable {
    func encode(to output: inout BufferEncoder) {
        self.id.encode(to: &output)
        self.properties.encode(to: &output)
    }
}
extension CPSSnapshot: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        let id: UInt64 = try .decode(from: &input)
        let properties: [CPSSnapshotEntry] = try .decode(from: &input)
        return .init(id: id, properties: properties)
    }
}
extension CPSSnapshot: SpanDecodable {
    static func decode(from input: inout SpanDecoder) throws(BufferDecodingError) -> Self {
        let id: UInt64 = try .decode(from: &input)
        let properties: [CPSSnapshotEntry] = try .decode(from: &input)
        return .init(id: id, properties: properties)
    }
}

// MARK: - encodedSize (the cheap size pass #24's reserve needs)

//  `collectionHeaderSize(_:)` (1 byte if count < 255, else 1 + 8-byte Int) is shared with
//  OrdoDictPayloads.swift; reuse it rather than redeclare.

func encodedSizeString(_ s: String) -> Int {
    let n: Int = s.utf8.count
    if  n == 0 { return 1 }                       // format byte only (.none)
    if  n <= 256 && !s.utf8.contains(0) {
        return 1 + n + 1                          // format byte + UTF-8 + trailing 0x00 (compact)
    }
    return 1 + 4 + 1 + n                          // format byte + 40-bit length + UTF-8 (long)
}
func encodedSizePropertyValue(_ v: CPSValue) -> Int {
    switch v {
    case .price, .quantity, .timestamp: return 1 + MemoryLayout<Int64>.size
    case .integer: return 1 + MemoryLayout<Int>.size
    case .enumeration: return 1 + 1
    case .text(let s): return 1 + encodedSizeString(s)
    case .structure(let values):
        var n: Int = 1 + collectionHeaderSize(values.count)
        for e: CPSValue in values { n += encodedSizePropertyValue(e) }
        return n
    }
}
func encodedSizeFieldUpdate(_ f: FieldUpdateLike) -> Int {
    switch f {
    case .replace(let v): return 1 + encodedSizePropertyValue(v)
    case .remove: return 1
    }
}
func encodedSizeUpdate(_ u: CPSUpdate) -> Int {
    var n: Int = MemoryLayout<UInt64>.size + collectionHeaderSize(u.properties.count)
    for e: CPSUpdateEntry in u.properties {
        n += MemoryLayout<UInt64>.size + encodedSizeFieldUpdate(e.value)
    }
    return n
}
func encodedSizeSnapshot(_ s: CPSSnapshot) -> Int {
    var n: Int = MemoryLayout<UInt64>.size + collectionHeaderSize(s.properties.count)
    for e: CPSSnapshotEntry in s.properties {
        n += MemoryLayout<UInt64>.size + encodedSizePropertyValue(e.value)
    }
    return n
}
func encodedSizeUpdateBatch(_ b: [CPSUpdate]) -> Int {
    var n: Int = collectionHeaderSize(b.count)
    for u: CPSUpdate in b { n += encodedSizeUpdate(u) }
    return n
}
func encodedSizeSnapshotBatch(_ b: [CPSSnapshot]) -> Int {
    var n: Int = collectionHeaderSize(b.count)
    for s: CPSSnapshot in b { n += encodedSizeSnapshot(s) }
    return n
}

// MARK: - #24 SpanEncoder caller-loops (no SpanEncodable protocol; write header + leaf per element)

func spanEncodePropertyValue(_ v: CPSValue, into s: inout SpanEncoder) {
    switch v {
    case .price(let x):
        s.append(PVTag.price.rawValue)
        s.appendLittleEndian(x)
    case .quantity(let x):
        s.append(PVTag.quantity.rawValue)
        s.appendLittleEndian(x)
    case .timestamp(let x):
        s.append(PVTag.timestamp.rawValue)
        s.appendLittleEndian(x)
    case .integer(let x):
        s.append(PVTag.integer.rawValue)
        s.appendLittleEndian(x)
    case .enumeration(let x):
        s.append(PVTag.enumeration.rawValue)
        s.append(x)
    case .text(let str):
        s.append(PVTag.text.rawValue)
        s.append(str)
    case .structure(let values):
        s.append(PVTag.structure.rawValue)
        s.append(collectionHeader: values.count)
        for e: CPSValue in values { spanEncodePropertyValue(e, into: &s) }
    }
}
func spanEncodeFieldUpdate(_ f: FieldUpdateLike, into s: inout SpanEncoder) {
    switch f {
    case .replace(let v):
        s.append(FUTag.replace.rawValue)
        spanEncodePropertyValue(v, into: &s)
    case .remove:
        s.append(FUTag.remove.rawValue)
    }
}
func spanEncodeUpdate(_ u: CPSUpdate, into s: inout SpanEncoder) {
    s.appendLittleEndian(u.id)
    s.append(collectionHeader: u.properties.count)
    for e: CPSUpdateEntry in u.properties {
        s.appendLittleEndian(e.key.raw)
        spanEncodeFieldUpdate(e.value, into: &s)
    }
}
func spanEncodeSnapshot(_ snap: CPSSnapshot, into s: inout SpanEncoder) {
    s.appendLittleEndian(snap.id)
    s.append(collectionHeader: snap.properties.count)
    for e: CPSSnapshotEntry in snap.properties {
        s.appendLittleEndian(e.key.raw)
        spanEncodePropertyValue(e.value, into: &s)
    }
}
func spanEncodeUpdateBatch(_ b: [CPSUpdate], into s: inout SpanEncoder) {
    s.append(collectionHeader: b.count)
    for u: CPSUpdate in b { spanEncodeUpdate(u, into: &s) }
}
func spanEncodeSnapshotBatch(_ b: [CPSSnapshot], into s: inout SpanEncoder) {
    s.append(collectionHeader: b.count)
    for snap: CPSSnapshot in b { spanEncodeSnapshot(snap, into: &s) }
}

// MARK: - Wire helpers

func updateBatchBuf23(_ b: [CPSUpdate]) -> [UInt8] {
    var e: BufferEncoder = .init(capacity: encodedSizeUpdateBatch(b))
    b.encode(to: &e)
    return e.finalize()
}
func snapshotBatchBuf23(_ b: [CPSSnapshot]) -> [UInt8] {
    var e: BufferEncoder = .init(capacity: encodedSizeSnapshotBatch(b))
    b.encode(to: &e)
    return e.finalize()
}
func updateBatchSpan24(_ b: [CPSUpdate]) -> [UInt8] {
    let size: Int = encodedSizeUpdateBatch(b)
    let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: Swift.max(size, 1), alignment: 1)
    defer { reserved.deallocate() }
    let region: UnsafeMutableRawBufferPointer = .init(rebasing: reserved[0 ..< size])
    var s: SpanEncoder = .init(OutputRawSpan(buffer: region, initializedCount: 0))
    spanEncodeUpdateBatch(b, into: &s)
    let written: Int = s.finalize()
    return [UInt8](UnsafeRawBufferPointer(rebasing: reserved[0 ..< written]))
}
func snapshotBatchSpan24(_ b: [CPSSnapshot]) -> [UInt8] {
    let size: Int = encodedSizeSnapshotBatch(b)
    let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: Swift.max(size, 1), alignment: 1)
    defer { reserved.deallocate() }
    let region: UnsafeMutableRawBufferPointer = .init(rebasing: reserved[0 ..< size])
    var s: SpanEncoder = .init(OutputRawSpan(buffer: region, initializedCount: 0))
    spanEncodeSnapshotBatch(b, into: &s)
    let written: Int = s.finalize()
    return [UInt8](UnsafeRawBufferPointer(rebasing: reserved[0 ..< written]))
}

// MARK: - Fixtures (built ONCE outside any measured region)

//  The 12 MarketData computed-property identifiers, with the literal base62 ids from
//  MarketData (cps).swift for traceability. We assign distinct UInt64 raws (Frostflake-shaped) so
//  JSON renders ~11-char base62 keys and the binary wire writes 8 bytes.
enum CPSFields {
    static func id(_ index: Int) -> PropertyID { .init(raw: 0x4A50_0000_0000_0000 &+ UInt64(index)) }

    static let exchangeTimestamp: PropertyID = id(0)   // "JRK89gCqgGE"
    static let bidPrice: PropertyID = id(1)            // "JNp1Z2rZ4gE"
    static let bidQuantity: PropertyID = id(2)         // "JNp1ZFwcixn"
    static let askPrice: PropertyID = id(3)            // "JNp1Z9Q5tpW"
    static let askQuantity: PropertyID = id(4)         // "JNp1ZNV9Z74"
    static let lastPrice: PropertyID = id(5)           // "JPge1pLastr"
    static let lastQuantity: PropertyID = id(6)        // "HvLastQv31Y"
    static let marketPhase: PropertyID = id(7)         // "JHY6PPhasen"
    static let auctionIndicativePrice: PropertyID = id(8)
    static let auctionIndicativeQuantity: PropertyID = id(9)
    static let auctionImbalanceQuantity: PropertyID = id(10)
    static let auctionImbalanceSide: PropertyID = id(11)
}

enum CPSFixtures {
    /// One sparse BestPrice Update for instrument `id`: the 4 BBO fields (bid/ask price+qty), each a
    /// FieldUpdate.replace, optionally + exchangeTimestamp. Values from `prng`.
    static func bestPriceUpdate(id: UInt64, withTimestamp: Bool, prng: inout CPSSplitMix64) -> CPSUpdate {
        func price() -> Int64 { Int64(bitPattern: prng.next() & 0x0000_00FF_FFFF_FFFF) }
        func qty() -> Int64 { Int64(bitPattern: prng.next() & 0x0000_0000_000F_FFFF) }
        var entries: [CPSUpdateEntry] = [
            .init(key: CPSFields.bidPrice, value: .replace(.price(price()))),
            .init(key: CPSFields.bidQuantity, value: .replace(.quantity(qty()))),
            .init(key: CPSFields.askPrice, value: .replace(.price(price()))),
            .init(key: CPSFields.askQuantity, value: .replace(.quantity(qty()))),
        ]
        if  withTimestamp {
            entries.insert(
                .init(key: CPSFields.exchangeTimestamp, value: .replace(.timestamp(prng.next()))),
                at: 0
            )
        }
        return .init(id: id, properties: entries)
    }

    /// A full 12-field MarketData snapshot for instrument `id` (the subscribe-time table).
    static func marketDataSnapshot(id: UInt64, prng: inout CPSSplitMix64) -> CPSSnapshot {
        func price() -> Int64 { Int64(bitPattern: prng.next() & 0x0000_00FF_FFFF_FFFF) }
        func qty() -> Int64 { Int64(bitPattern: prng.next() & 0x0000_0000_000F_FFFF) }
        let entries: [CPSSnapshotEntry] = [
            .init(key: CPSFields.exchangeTimestamp, value: .timestamp(prng.next())),
            .init(key: CPSFields.bidPrice, value: .price(price())),
            .init(key: CPSFields.bidQuantity, value: .quantity(qty())),
            .init(key: CPSFields.askPrice, value: .price(price())),
            .init(key: CPSFields.askQuantity, value: .quantity(qty())),
            .init(key: CPSFields.lastPrice, value: .price(price())),
            .init(key: CPSFields.lastQuantity, value: .quantity(qty())),
            .init(key: CPSFields.marketPhase, value: .enumeration(UInt8(prng.next() % 12))),
            .init(key: CPSFields.auctionIndicativePrice, value: .price(price())),
            .init(key: CPSFields.auctionIndicativeQuantity, value: .quantity(qty())),
            .init(key: CPSFields.auctionImbalanceQuantity, value: .quantity(qty())),
            .init(key: CPSFields.auctionImbalanceSide, value: .enumeration(UInt8(prng.next() % 3))),
        ]
        return .init(id: id, properties: entries)
    }

    /// A batch of N sparse BestPrice updates (the throttled NotificationBatch over N instruments).
    static func bestPriceBatch(_ n: Int, withTimestamp: Bool) -> [CPSUpdate] {
        var prng: CPSSplitMix64 = .init(seed: 0x4250_0000_0000_0000 &+ UInt64(n) &+ (withTimestamp ? 1 : 0))
        var batch: [CPSUpdate] = []
        batch.reserveCapacity(n)
        for i: Int in 0 ..< n {
            batch.append(bestPriceUpdate(id: 0x9000_0000_0000_0000 &+ UInt64(i), withTimestamp: withTimestamp, prng: &prng))
        }
        return batch
    }

    /// A batch of N full MarketData snapshots (subscribe-time).
    static func snapshotBatch(_ n: Int) -> [CPSSnapshot] {
        var prng: CPSSplitMix64 = .init(seed: 0x5350_0000_0000_0000 &+ UInt64(n))
        var batch: [CPSSnapshot] = []
        batch.reserveCapacity(n)
        for i: Int in 0 ..< n {
            batch.append(marketDataSnapshot(id: 0xA000_0000_0000_0000 &+ UInt64(i), prng: &prng))
        }
        return batch
    }

    /// A single Update carrying one recursive `structure` PropertyValue (the expressibility stress).
    static func structureBatch() -> [CPSUpdate] {
        var prng: CPSSplitMix64 = .init(seed: 0x5354_5255_4354_0000)
        let nested: CPSValue = .structure([
            .price(Int64(bitPattern: prng.next())),
            .quantity(Int64(bitPattern: prng.next())),
            .text("SEK/USD/NOK"),
            .structure([.integer(42), .enumeration(3), .timestamp(prng.next())]),
        ])
        return [.init(id: 0xB000_0000_0000_0001, properties: [
            .init(key: CPSFields.bidPrice, value: .replace(nested)),
        ])]
    }
}

// MARK: - Correctness (asserted at fixture-build time, before any benchmark runs)

func updateBatchCorrect(_ b: [CPSUpdate]) -> Bool {
    do {
        let json: Data = try JSONEncoder().encode(b)
        guard try JSONDecoder().decode([CPSUpdate].self, from: json) == b else { return false }
        let bytes23: [UInt8] = updateBatchBuf23(b)
        var d23: BufferDecoder = .init(bytes23[...])
        guard try [CPSUpdate].decode(from: &d23) == b else { return false }
        let bytes24: [UInt8] = updateBatchSpan24(b)
        let ok24: Bool = try bytes24.withUnsafeBytes { (raw: UnsafeRawBufferPointer) throws -> Bool in
            var d: SpanDecoder = .init(RawSpan(_unsafeBytes: raw))
            return try [CPSUpdate].decode(from: &d) == b
        }
        guard ok24 else { return false }
        guard bytes23 == bytes24 else { return false }
        return true
    } catch {
        return false
    }
}
func snapshotBatchCorrect(_ b: [CPSSnapshot]) -> Bool {
    do {
        let json: Data = try JSONEncoder().encode(b)
        guard try JSONDecoder().decode([CPSSnapshot].self, from: json) == b else { return false }
        let bytes23: [UInt8] = snapshotBatchBuf23(b)
        var d23: BufferDecoder = .init(bytes23[...])
        guard try [CPSSnapshot].decode(from: &d23) == b else { return false }
        let bytes24: [UInt8] = snapshotBatchSpan24(b)
        let ok24: Bool = try bytes24.withUnsafeBytes { (raw: UnsafeRawBufferPointer) throws -> Bool in
            var d: SpanDecoder = .init(RawSpan(_unsafeBytes: raw))
            return try [CPSSnapshot].decode(from: &d) == b
        }
        guard ok24 else { return false }
        guard bytes23 == bytes24 else { return false }
        return true
    } catch {
        return false
    }
}

// MARK: - Registration

func registerCPSPayloadBenchmarks() {
    let metrics: [BenchmarkMetric] =
        [.wallClock, .instructions, .throughput] + BenchmarkMetric.memory + BenchmarkMetric.arc
    func config() -> Benchmark.Configuration { .init(metrics: metrics, timeUnits: .microseconds) }

    //  Register the 6 benchmarks (JSON / #23 / #24 x encode / decode) for an Update batch.
    func registerUpdateBatch(_ label: String, _ batch: [CPSUpdate]) {
        precondition(updateBatchCorrect(batch), "CPS \(label): roundtrip or #23/#24 byte mismatch")
        let jsonWire: [UInt8] = [UInt8](try! JSONEncoder().encode(batch))
        let wire23: [UInt8] = updateBatchBuf23(batch)
        let wire24: [UInt8] = updateBatchSpan24(batch)
        let cap: Int = encodedSizeUpdateBatch(batch)
        print("[CPS \(label)] wire bytes — JSON: \(jsonWire.count), #23: \(wire23.count), #24: \(wire24.count)")

        Benchmark.init("CPS \(label) JSON encode", configuration: config()) { benchmark in
            let encoder: JSONEncoder = .init()
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                blackHole(try encoder.encode(batch))
            }
        }
        Benchmark.init("CPS \(label) JSON decode", configuration: config()) { benchmark in
            let data: Data = Data(jsonWire)
            let decoder: JSONDecoder = .init()
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                blackHole(try decoder.decode([CPSUpdate].self, from: data))
            }
        }
        Benchmark.init("CPS \(label) #23 encode", configuration: config()) { benchmark in
            var buffer: [UInt8] = []
            buffer.reserveCapacity(cap)
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                buffer.removeAll(keepingCapacity: true)
                var e: BufferEncoder = .init(preallocated: buffer)
                buffer = []
                batch.encode(to: &e)
                buffer = e.finalize()
                blackHole(buffer.count)
            }
        }
        Benchmark.init("CPS \(label) #23 decode", configuration: config()) { benchmark in
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                let copy: [UInt8] = Array(wire23)
                var d: BufferDecoder = .init(copy[...])
                blackHole(try [CPSUpdate].decode(from: &d))
            }
        }
        Benchmark.init("CPS \(label) #24 encode", configuration: config()) { benchmark in
            let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: Swift.max(cap, 1), alignment: 1)
            defer { reserved.deallocate() }
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                let size: Int = encodedSizeUpdateBatch(batch)
                let region: UnsafeMutableRawBufferPointer = .init(rebasing: reserved[0 ..< size])
                var s: SpanEncoder = .init(OutputRawSpan(buffer: region, initializedCount: 0))
                spanEncodeUpdateBatch(batch, into: &s)
                blackHole(s.finalize())
            }
        }
        Benchmark.init("CPS \(label) #24 decode", configuration: config()) { benchmark in
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                wire24.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                    var d: SpanDecoder = .init(RawSpan(_unsafeBytes: raw))
                    blackHole(try! [CPSUpdate].decode(from: &d))
                }
            }
        }
    }

    func registerSnapshotBatch(_ label: String, _ batch: [CPSSnapshot]) {
        precondition(snapshotBatchCorrect(batch), "CPS \(label): roundtrip or #23/#24 byte mismatch")
        let jsonWire: [UInt8] = [UInt8](try! JSONEncoder().encode(batch))
        let wire23: [UInt8] = snapshotBatchBuf23(batch)
        let wire24: [UInt8] = snapshotBatchSpan24(batch)
        let cap: Int = encodedSizeSnapshotBatch(batch)
        print("[CPS \(label)] wire bytes — JSON: \(jsonWire.count), #23: \(wire23.count), #24: \(wire24.count)")

        Benchmark.init("CPS \(label) JSON encode", configuration: config()) { benchmark in
            let encoder: JSONEncoder = .init()
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                blackHole(try encoder.encode(batch))
            }
        }
        Benchmark.init("CPS \(label) JSON decode", configuration: config()) { benchmark in
            let data: Data = Data(jsonWire)
            let decoder: JSONDecoder = .init()
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                blackHole(try decoder.decode([CPSSnapshot].self, from: data))
            }
        }
        Benchmark.init("CPS \(label) #23 encode", configuration: config()) { benchmark in
            var buffer: [UInt8] = []
            buffer.reserveCapacity(cap)
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                buffer.removeAll(keepingCapacity: true)
                var e: BufferEncoder = .init(preallocated: buffer)
                buffer = []
                batch.encode(to: &e)
                buffer = e.finalize()
                blackHole(buffer.count)
            }
        }
        Benchmark.init("CPS \(label) #23 decode", configuration: config()) { benchmark in
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                let copy: [UInt8] = Array(wire23)
                var d: BufferDecoder = .init(copy[...])
                blackHole(try [CPSSnapshot].decode(from: &d))
            }
        }
        Benchmark.init("CPS \(label) #24 encode", configuration: config()) { benchmark in
            let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: Swift.max(cap, 1), alignment: 1)
            defer { reserved.deallocate() }
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                let size: Int = encodedSizeSnapshotBatch(batch)
                let region: UnsafeMutableRawBufferPointer = .init(rebasing: reserved[0 ..< size])
                var s: SpanEncoder = .init(OutputRawSpan(buffer: region, initializedCount: 0))
                spanEncodeSnapshotBatch(batch, into: &s)
                blackHole(s.finalize())
            }
        }
        Benchmark.init("CPS \(label) #24 decode", configuration: config()) { benchmark in
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                wire24.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                    var d: SpanDecoder = .init(RawSpan(_unsafeBytes: raw))
                    blackHole(try! [CPSSnapshot].decode(from: &d))
                }
            }
        }
    }

    //  (1) Sparse BestPrice tick (4 BBO fields) — DirectMarketData .distributed delta. N=1 is a
    //      single tick; N in {100, 1000, 5000} are throttled NotificationBatches over N instruments.
    for n: Int in [1, 100, 1_000, 5_000] {
        registerUpdateBatch("bestPrice4 N=\(n)", CPSFixtures.bestPriceBatch(n, withTimestamp: false))
    }
    //  (2) BestPrice + exchangeTimestamp (5 fields) — common variant.
    for n: Int in [1, 1_000] {
        registerUpdateBatch("bestPrice5 N=\(n)", CPSFixtures.bestPriceBatch(n, withTimestamp: true))
    }
    //  (3) Full 12-field MarketData snapshot — subscribe-time ComputedPropertyTable.
    for n: Int in [1, 100, 1_000] {
        registerSnapshotBatch("marketDataFull N=\(n)", CPSFixtures.snapshotBatch(n))
    }
    //  (4) Recursive `structure` PropertyValue — expressibility stress (indirect case).
    registerUpdateBatch("structure", CPSFixtures.structureBatch())
}
