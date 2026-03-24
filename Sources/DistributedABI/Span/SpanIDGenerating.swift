/// Protocol for pluggable span ID generation.
public protocol SpanIDGenerating: Sendable {
    func nextIdentifier() -> UInt64
}

/// Default ID generator using Swift's built-in random number generator.
public struct RandomSpanIDGenerator: SpanIDGenerating {
    public init() {}

    @inlinable @inline(__always) public func nextIdentifier() -> UInt64 { .random(in: 1 ... .max) }
}

extension SpanContext {
    /// Stored as function pointer for zero-overhead dispatch.
    nonisolated(unsafe) internal static var _nextIdentifier: @Sendable () -> UInt64 = RandomSpanIDGenerator().nextIdentifier

    @usableFromInline @inline(__always) internal static var nextIdentifier: UInt64 { _nextIdentifier() }

    /// Configure the ID generator. Call once at startup (like `LoggingSystem.bootstrap`).
    public static func bootstrap(_ generator: some SpanIDGenerating) {
        _nextIdentifier = generator.nextIdentifier
    }
}
