struct Rand {
    private var x: UInt32 = 0
    private var y: UInt32 = 0

    // XorShift(copied from golang), see below
    // https://www.jstatsoft.org/article/view/v008i14/xorshift.pdf
    // https://lemire.me/blog/2016/06/27/a-fast-alternative-to-the-modulo-reduction/
    @inlinable mutating func fast(n: UInt32) -> UInt32 {
        x ^= x << 17
        x = x ^ y ^ x >> 7 ^ y >> 16
        (x, y) = (y, x)
        return UInt32((UInt64(x &+ y) &* UInt64(n)) >> 32)
    }

    init() {
        func memoryAddress(_ p: UnsafeRawPointer) -> UInt {
            UInt(bitPattern: p)
        }

        let p = memoryAddress(&self)
        x = UInt32(p >> 32)
        y = UInt32(p & (UInt.max >> 32))
        if x | y == 0 {
            y = UInt32(p == 0 ? 1 : p)
        }
    }
}
