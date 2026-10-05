#if DEBUG
    /// SplitMix64: a small, fast generator whose sequence depends only on its seed. The one seeded generator of
    /// the fakes and of `LedgerTestSupport` (testing-strategy §3 rule 5): the link bus draws from it, and so do
    /// the session contract's scripts.
    public struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64

        public init(seed: UInt64) {
            state = seed
        }

        public mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }
#endif
