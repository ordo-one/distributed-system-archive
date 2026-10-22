/// A seeded generator of 64-bit numbers, Steele, Lea and Flood’s SplitMix64. The same seed
/// gives the same numbers on every platform, so a fuzz failure replays from its seed.
struct SplitMix64 {
    var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }
}
extension SplitMix64: RandomNumberGenerator {
    mutating func next() -> UInt64 {
        self.state &+= 0x9e37_79b9_7f4a_7c15
        var z: UInt64 = self.state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}
