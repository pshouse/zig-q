const std = @import("std");

/// Deterministic xorshift64* RNG — seedable and replayable.
pub const SeededRng = struct {
    state: u64,
    offset: u16 = 0,

    pub fn init(seed: u64) SeededRng {
        return .{
            .state = if (seed == 0) 0xdeadbeef else seed,
            .offset = 0,
        };
    }

    pub fn nextU8(self: *SeededRng) u8 {
        const word = self.nextU64();
        self.offset +%= 1;
        return @truncate(word);
    }

    pub fn rollDie(self: *SeededRng, sides: u8) u8 {
        std.debug.assert(sides >= 1);
        const r = self.nextU8();
        return 1 + (r % sides);
    }

    fn nextU64(self: *SeededRng) u64 {
        var x = self.state;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.state = x;
        return x *% 0x2545F4914F6CDD1D;
    }
};

test "seeded rng is deterministic" {
    var a = SeededRng.init(42);
    var b = SeededRng.init(42);
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        try std.testing.expectEqual(a.rollDie(6), b.rollDie(6));
    }
}

test "rollDie stays in 1..sides" {
    var rng = SeededRng.init(99);
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const r = rng.rollDie(6);
        try std.testing.expect(r >= 1 and r <= 6);
    }
}