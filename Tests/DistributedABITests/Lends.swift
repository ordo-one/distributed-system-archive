import Synchronization

/// The number of times a ``Lent`` value, or any copy of it, has lent its bytes.
final class Lends: Sendable {
    let count: Atomic<Int>

    init() {
        self.count = .init(0)
    }
}
