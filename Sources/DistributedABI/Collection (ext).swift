extension Collection {
    @inlinable var header: CollectionHeader { .init(count: self.count) }
}
