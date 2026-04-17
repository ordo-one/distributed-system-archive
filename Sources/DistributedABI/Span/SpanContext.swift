/// Lightweight context for correlating log entries and tracing operations across process boundaries.
///
/// A `SpanContext` carries three identifiers:
/// - ``traceIdentifier``: shared by all spans in a single trace (end-to-end request)
/// - ``spanIdentifier``: unique to each operation within the trace
/// - ``parentSpanIdentifier``: links this span to its parent (0 for root spans)
///
/// ## Creating spans
///
/// Use ``makeTrace()`` to start a new root trace, or ``makeChildSpan()`` to create
/// a child within an existing trace. For root spans, `traceIdentifier` and `spanIdentifier` share the
/// same value (one Frostflake generation instead of two).
///
/// ## Propagation
///
/// The ``current`` task-local carries the active span through the Swift Concurrency task tree.
/// Use ``withSpan(_:)`` / ``withChildSpan(_:)`` (and their async overloads) to
/// set ``current`` for the duration of a closure. Across process boundaries (distributed actor
/// calls), the context is propagated via `TraceHook` in `InvocationEnvelope`.
///
/// ### Why `@TaskLocal`
///
/// Passing `SpanContext` as an explicit function argument is the preferred propagation method
/// (zero overhead). `@TaskLocal` is used only where explicit passing is not possible — for
/// example across `distributed func` boundaries where the wire format is controlled by
/// `DistributedTargetInvocationEncoder`, or across async notification streams that sever the
/// task tree.
///
/// `@TaskLocal` was chosen over `Baggage.$current.withValue` (`ServiceContext` from
/// swift-service-context) after benchmarking. `ServiceContext.$current.withValue` adds ~600ns
/// per boundary crossing. A bare `@TaskLocal<SpanContext>` with a 16-byte value type adds
/// ~90ns — about 6x cheaper.
///
/// Benchmark: `prototype-experiments/Benchmarks/ThreadLocal/ThreadLocal.swift`
/// (tests 9–14 compare `@TaskLocal` vs explicit argument for a minimal `SpanContext`).
@frozen public struct SpanContext: Sendable, Equatable {
    /// Identifier shared by all spans in the same trace. Generated once at the root.
    public let traceIdentifier: UInt64
    /// Unique identifier for this operation. Each call to ``makeChildSpan()`` generates a new one.
    public let spanIdentifier: UInt64
    /// The ``spanIdentifier`` of the parent span, or 0 for root spans.
    public let parentSpanIdentifier: UInt64

    /// Sentinel for "no active trace". Named `.untraced` (not `.none`) to avoid ambiguity with `Optional.none`.
    public static let untraced = SpanContext(traceIdentifier: 0, spanIdentifier: 0, parentSpanIdentifier: 0)

    /// Whether this context carries a valid trace (`traceIdentifier != 0`).
    @inlinable @inline(__always) public var isValid: Bool { traceIdentifier != 0 }

    @inlinable @inline(__always) public init(traceIdentifier: UInt64, spanIdentifier: UInt64, parentSpanIdentifier: UInt64 = 0) {
        self = SpanContext(_traceIdentifier: traceIdentifier, _spanIdentifier: spanIdentifier, _parentSpanIdentifier: parentSpanIdentifier)
    }

    @usableFromInline internal init(_traceIdentifier: UInt64, _spanIdentifier: UInt64, _parentSpanIdentifier: UInt64) {
        self.traceIdentifier = _traceIdentifier
        self.spanIdentifier = _spanIdentifier
        self.parentSpanIdentifier = _parentSpanIdentifier
    }

    /// Create a new root trace. The `traceIdentifier` and `spanIdentifier` share the same value for root spans.
    @inlinable @inline(__always) public static func makeTrace() -> SpanContext {
        let id = generateIdentifier()
        return SpanContext(traceIdentifier: id, spanIdentifier: id, parentSpanIdentifier: 0)
    }

    /// Create a child span inheriting this context's `traceIdentifier`.
    @inlinable @inline(__always) public func makeChildSpan() -> SpanContext {
        SpanContext(traceIdentifier: traceIdentifier, spanIdentifier: Self.generateIdentifier(), parentSpanIdentifier: spanIdentifier)
    }

    /// The active span for the current task. Defaults to ``untraced``.
    @TaskLocal public static var current: SpanContext = .untraced

    /// Run body within a span. Creates a new root trace if none active, or a child span if already in a trace.
    @inlinable @inline(__always) public static func withSpan<T>(_ body: () throws -> T) rethrows -> T {
        let span = current.isValid ? current.makeChildSpan() : .makeTrace()
        return try $current.withValue(span, operation: body)
    }

    /// Run body within a span (async). Creates a new root trace if none active, or a child span if already in a trace.
    @inlinable @inline(__always) public static func withSpan<T>(
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async rethrows -> T {
        let span = current.isValid ? current.makeChildSpan() : .makeTrace()
        return try await $current.withValue(span, operation: body, isolation: isolation)
    }

    /// Run body as a child span of this context. If this context is untraced, runs body without setting a span.
    @inlinable @inline(__always) public func withChildSpan<T>(_ body: () throws -> T) rethrows -> T {
        guard isValid else { return try body() }
        return try Self.$current.withValue(makeChildSpan(), operation: body)
    }

    /// Run body as a child span of this context (async). If this context is untraced, runs body without setting a span.
    @inlinable @inline(__always) public func withChildSpan<T>(
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async rethrows -> T {
        guard isValid else { return try await body() }
        return try await Self.$current.withValue(makeChildSpan(), operation: body, isolation: isolation)
    }

    @usableFromInline @inline(__always) internal static func generateIdentifier() -> UInt64 {
        nextIdentifier
    }
}
