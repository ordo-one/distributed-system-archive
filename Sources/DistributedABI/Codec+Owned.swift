//  Owned-buffer convenience entry points.
//
//  These bridge the borrowed-span witnesses to callers holding an owned `[UInt8]`
//  / `ArraySlice<UInt8>` (decode) or wanting a fresh `[UInt8]` (encode). The
//  owned decode path borrows the array's storage as a `RawSpan` via
//  `withUnsafeBytes` — there is NO copy of the source bytes. The owned encode
//  path runs the `encodedSize` pass once, reserves exactly that many bytes, and
//  writes the wire bytes straight into the new array's uninitialized storage.

extension BufferDecodable {
    /// Decodes a value from a borrowed `RawSpan`, starting at the beginning.
    @inlinable public static func decode(
        from input: RawSpan
    ) throws(BufferDecodingError) -> Self {
        var index: Int = 0
        return try Self.decode(from: input, at: &index)
    }

    /// Decodes a value from an owned byte slice, borrowing it as a `RawSpan`
    /// (no copy).
    @inlinable public static func decode(
        _ bytes: ArraySlice<UInt8>
    ) throws(BufferDecodingError) -> Self {
        var result: Self? = nil
        var failure: BufferDecodingError? = nil
        bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var index: Int = 0
            let span: RawSpan = .init(_unsafeBytes: raw)
            do {
                result = try Self.decode(from: span, at: &index)
            } catch let error as BufferDecodingError {
                failure = error
            } catch {
                failure = .arbitrary(error)
            }
        }
        if let failure: BufferDecodingError { throw failure }
        return result.unsafelyUnwrapped
    }

    /// Decodes a value from an owned byte array, borrowing it as a `RawSpan`
    /// (no copy).
    @inlinable public static func decode(
        _ bytes: borrowing [UInt8]
    ) throws(BufferDecodingError) -> Self {
        try Self.decode(bytes[...])
    }
}

extension BufferEncodable {
    /// Encodes the value into a freshly allocated `[UInt8]`, sized by a single
    /// ``encodedSize`` pass. The wire bytes are written straight into the array's
    /// uninitialized storage; the array is trimmed to the exact bytes written.
    @inlinable public func encoded() -> [UInt8] {
        let capacity: Int = self.encodedSize
        if capacity == 0 { return [] }
        return [UInt8].init(unsafeUninitializedCapacity: capacity) {
            (buffer: inout UnsafeMutableBufferPointer<UInt8>, count: inout Int) in
            var output: OutputRawSpan = .init(
                buffer: .init(buffer),
                initializedCount: 0
            )
            self.encode(into: &output)
            let written: Int = output.byteCount
            _ = consume output
            count = written
        }
    }

    /// Encodes the value into a caller-provided reserved region (the LMDB
    /// `MDB_RESERVE` case), returning the number of bytes written. The region
    /// must be at least ``encodedSize`` bytes.
    @inlinable public func encode(into region: UnsafeMutableRawBufferPointer) -> Int {
        var output: OutputRawSpan = .init(buffer: region, initializedCount: 0)
        self.encode(into: &output)
        let written: Int = output.byteCount
        _ = consume output
        return written
    }
}
