// simple
// unexpected
// concrete
// credible
// emotion
// story

const std = @import("std");

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    print("All your {s} are belong to us.", .{"die"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    var mySq = RndByteSq.init(0);
    // const myTarget = 18;
    var d6 = D.init(6);
    var i: usize = 0;
    var results_buffer: [24]u64 = undefined;
    var myRoll = Throw{.n_times = 4, .drop = Drop.L, .results = &results_buffer};
    
    var buffer: [6]Throw = undefined;
    var myRolls = List(Throw){
        .items = &buffer,
        .len = 0,
    };

    while ( myRolls.len < 6 ) {
        // var throw = ;
        myRoll.sum = 0;
        d6.roll(&mySq, &myRoll);
        // getRnd(&mySq, 6);
        i += 1;
        print("myRoll {}: {}", .{i, myRoll.sum});
        if (myRoll.sum > 7) {
            myRolls.items[myRolls.len] = myRoll;
            myRolls.len += 1;
        }
    }
    try stdout.print("You rolled ", .{});

    for (myRolls.items) |value| {
        try stdout.print("{any} ", .{value.sum});
    }
    try bw.flush(); // don't forget to flush!
}
fn List(comptime T: type) type {
    return struct {
        items: []T,
        len: usize,
    };
}
pub const D = struct {
    sides: u8,

    pub fn init(n_sides: u8) D {
        return .{
            .sides = n_sides,

        };
    }

    pub fn roll(self: *D, gen: *RndByteSq, throw: *Throw) void {
        var i: usize = 0;
        //var result: u64 = 0;
        // var throw = Throw{};

        while (i<throw.n_times) {
            const r = getRnd(gen, self.sides);
            print("roll {}: {}", .{i+1,r});
            //throw.result += r;
            throw.append(r);
            i+=1;
        }
        
        throw.sum += throw.b;

        if (throw.drop) | value | {
            print("throw.drop: {}",.{value});
            switch (value) {
                Drop.L => {
                    throw.sum -= throw.min;
                    print("dropped: {}", .{throw.min});
                }, 
                Drop.H => {
                    throw.sum -= throw.max;
                },
            }
        }
        
       // return throw;
    }
};
const Drop = enum {
    L,
    H,
};
pub const Throw = struct {
    n_times: u64 = 1,
    b: u64 = 0,
    drop: ?Drop = null,
    i: u12 = 0,
    results: []u64 ,
    min: u64 = 0,
    max: u64 = 0,
    sum: u64 = 0,
    
    pub fn append(self: *Throw, result: u64) void {
        self.results[self.i] = result;
        self.sum += result;
        if (self.i == 0) {
            self.min = result;
            self.max = result;
        }
        if (result < self.min) {
            self.min = result;    
        }
        if (result > self.max) {
            self.max = result;
        }
         
        self.i +%= 1; 
    }
};

pub fn getRnd(gen: *RndByteSq, d: u8) u64 {
    // var i: usize = 0;
    // var result: u64 = 0;
    const rndByteSize = @bitSizeOf(@TypeOf(byteSq[0]));
    const fullByte = 1 << rndByteSize;
    // print("fullByte: {}", .{fullByte});
    const rndByte = gen.next();
    const unit = @intToFloat(f64, rndByte) / fullByte;
    // print("unit: {}", .{unit});
    const rndNum = d - @floatToInt(u8, unit * @intToFloat(f64, d));
    
    return rndNum;
}

const RndByteSq = struct {
    seed: u12,
    offset: u12,
    n: u64,

    pub fn init(start_seed: u12) RndByteSq {
        return .{
            .seed = start_seed,
            .offset = 0,
            .n = 0,
        };
    }
    pub fn next(self: *RndByteSq) u8 {
        var i: u12 = self.seed +% self.offset;
        var result: u8 = byteSq[i];
        self.n +%= 1;
        self.offset +%= 1;
        print("n: {}, next({}): {}", .{ self.n, i, result });
        return result;
    }
};

pub fn print(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
    std.debug.print("\n", .{});
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

const byteSq = [_]u8{
    0x49, 0xab, 0x90, 0x18, 0xd6, 0xed, 0xcd, 0x42, 0x39, 0xfc, 0xe2, 0x83, 0xdf, 0xd9, 0x61, 0x41,
    0x4b, 0xb2, 0xcf, 0xda, 0x25, 0xee, 0x17, 0x86, 0xdc, 0x1c, 0x52, 0x6d, 0xd6, 0x1a, 0xaa, 0xa5,
    0x9a, 0x92, 0xe7, 0x19, 0x03, 0x6d, 0xd4, 0x4d, 0x5f, 0x9c, 0x83, 0x82, 0xa6, 0x9f, 0xc3, 0x7d,
    0x37, 0xaa, 0x09, 0x54, 0x10, 0xf4, 0x0b, 0x0f, 0x2d, 0x8e, 0x66, 0xdc, 0xc3, 0x78, 0x1e, 0x83,
    0xa9, 0xe4, 0xa3, 0x90, 0x14, 0xb3, 0x17, 0x3c, 0xe7, 0xd6, 0x7a, 0x5b, 0xeb, 0x08, 0xea, 0x1a,
    0xe3, 0x5c, 0xc9, 0xc3, 0x41, 0x7a, 0x34, 0x1e, 0xb6, 0x08, 0x6d, 0xbb, 0xde, 0x15, 0x69, 0xa4,
    0x12, 0x7c, 0x59, 0x56, 0xea, 0x07, 0x73, 0xbe, 0x20, 0x8c, 0xaa, 0x50, 0xb4, 0x5b, 0xbb, 0xea,
    0xc0, 0xc0, 0x89, 0x6c, 0x52, 0xc6, 0x33, 0x7f, 0xef, 0x1e, 0xf3, 0xb6, 0x3a, 0x9c, 0x84, 0x09,
    0xe2, 0xa8, 0x05, 0x18, 0xea, 0x60, 0x12, 0x37, 0xb4, 0x4f, 0x1b, 0x39, 0x8c, 0x42, 0x5e, 0x73,
    0x83, 0xd0, 0x57, 0x15, 0x38, 0x0e, 0x43, 0x16, 0x62, 0xae, 0xba, 0x0c, 0x9e, 0xd6, 0xd3, 0x8e,
    0x8b, 0xa2, 0xeb, 0x08, 0x62, 0xfc, 0xd4, 0x47, 0x6d, 0xdf, 0x7b, 0xfb, 0x87, 0xfa, 0xb3, 0x61,
    0x92, 0xeb, 0x77, 0x40, 0x24, 0x28, 0x7a, 0xf5, 0xda, 0xfe, 0x93, 0x31, 0x81, 0x3d, 0xe5, 0x06,
    0x13, 0xa6, 0x1e, 0xc3, 0x77, 0xaa, 0x25, 0x0b, 0xa9, 0xd7, 0x61, 0x24, 0x02, 0xa1, 0xcd, 0x89,
    0x46, 0xb4, 0x59, 0xcc, 0x06, 0x48, 0x5d, 0xa2, 0xf7, 0xb5, 0xc4, 0x48, 0x27, 0x18, 0xc2, 0x96,
    0x97, 0x1e, 0x61, 0x36, 0xee, 0x83, 0x11, 0x01, 0x89, 0xd7, 0x74, 0x42, 0xe0, 0x66, 0x67, 0x28,
    0xce, 0xdd, 0xca, 0x60, 0x8d, 0x79, 0xc6, 0x81, 0x4e, 0x00, 0xad, 0x9d, 0xb5, 0x37, 0xec, 0x7d,
    0x49, 0x0e, 0x0b, 0xd2, 0xdd, 0x05, 0x1a, 0x1d, 0xbb, 0x78, 0x4f, 0x08, 0x3d, 0x71, 0x92, 0x39,
    0x2e, 0x09, 0xbd, 0x1c, 0x72, 0x00, 0x8f, 0x58, 0x3b, 0x82, 0x76, 0x91, 0xd2, 0xe8, 0xcd, 0xa6,
    0x4b, 0x41, 0xfa, 0xfb, 0x0e, 0x80, 0x8c, 0x83, 0x0a, 0x3d, 0xb7, 0x0b, 0xd6, 0xbb, 0xbc, 0xb4,
    0x88, 0x3a, 0xa0, 0x46, 0x20, 0x54, 0x7f, 0x62, 0x2b, 0x13, 0x5a, 0x4a, 0x42, 0xaa, 0x1b, 0x7d,
    0x3f, 0x80, 0x43, 0xf0, 0xff, 0xf4, 0x03, 0x34, 0x80, 0x38, 0x60, 0x65, 0x7c, 0x48, 0x9b, 0x2f,
    0x7a, 0x16, 0x9f, 0xca, 0x86, 0x88, 0xff, 0xe8, 0xff, 0x3b, 0x54, 0xe3, 0x41, 0x85, 0x2b, 0xeb,
    0x1c, 0x84, 0x11, 0xa3, 0x7a, 0x24, 0xde, 0x5b, 0x44, 0xa9, 0x43, 0x76, 0x82, 0x2a, 0xa2, 0x13,
    0x08, 0x75, 0xd9, 0x8e, 0x0d, 0x23, 0x1e, 0x74, 0x1d, 0xc0, 0x4b, 0x6e, 0x6b, 0x54, 0xbd, 0x64,
    0x8b, 0xa3, 0x55, 0x46, 0x4c, 0xa5, 0xd0, 0xf1, 0xf3, 0x42, 0xa6, 0x51, 0x50, 0x4e, 0xf3, 0x46,
    0x84, 0xe6, 0xba, 0xe9, 0x27, 0x4f, 0xff, 0x8c, 0xc7, 0xd5, 0x1c, 0x57, 0xe7, 0x7b, 0x73, 0xa6,
    0xa0, 0x1b, 0xe7, 0xea, 0x39, 0x45, 0xe9, 0xc7, 0x46, 0x7f, 0x68, 0xf3, 0x7a, 0xc9, 0x04, 0xd1,
    0x87, 0x89, 0x04, 0x16, 0x8d, 0x24, 0xac, 0x98, 0xf6, 0x7f, 0x18, 0xa7, 0xb3, 0x92, 0x23, 0x1b,
    0x41, 0x35, 0xc5, 0x19, 0x20, 0x66, 0x7d, 0xf3, 0xf3, 0x68, 0xfd, 0x15, 0x67, 0x2b, 0x4e, 0xdf,
    0x60, 0x8e, 0x42, 0x2f, 0xbd, 0x33, 0xf6, 0x4d, 0x50, 0x62, 0x12, 0x88, 0x7d, 0xd3, 0x6d, 0xac,
    0x57, 0x17, 0x68, 0x51, 0xd7, 0xfb, 0x96, 0x8d, 0x56, 0x88, 0x62, 0xbb, 0x8d, 0x2a, 0x43, 0x9b,
    0x9c, 0xac, 0xed, 0x05, 0xc7, 0xd9, 0xe2, 0xe8, 0x17, 0xd7, 0x14, 0x10, 0x81, 0x5e, 0x5a, 0x03,
    0x48, 0x4d, 0xda, 0xe8, 0x8c, 0x84, 0x55, 0x28, 0x0f, 0xd1, 0x3a, 0xa5, 0x92, 0x2a, 0xb1, 0xbf,
    0xf3, 0x82, 0x79, 0xf1, 0xed, 0x5a, 0x9b, 0x6f, 0x39, 0xcc, 0xe1, 0xd8, 0xd1, 0xad, 0xcd, 0x95,
    0xb0, 0x58, 0x02, 0x95, 0xf6, 0xaf, 0xd1, 0xbf, 0x9a, 0x0b, 0xf0, 0xaa, 0xa2, 0x58, 0x4d, 0x9b,
    0xa9, 0x7d, 0x59, 0x83, 0x5e, 0x56, 0x03, 0xbe, 0xf8, 0xcb, 0xaf, 0x33, 0x89, 0x5e, 0xb8, 0x7c,
    0x1c, 0xd0, 0x3f, 0x4d, 0xc2, 0x6c, 0xa4, 0xb0, 0xfe, 0x16, 0x31, 0x1e, 0xba, 0x79, 0xef, 0x62,
    0xb7, 0xa8, 0xf0, 0xb9, 0x3a, 0x10, 0xf3, 0xc2, 0x81, 0x1a, 0x6c, 0x02, 0xfa, 0xef, 0x17, 0xc6,
    0x1f, 0x1d, 0x67, 0x98, 0x5d, 0x61, 0x59, 0x08, 0xc7, 0x65, 0x34, 0x82, 0x35, 0xd2, 0x05, 0x9f,
    0x10, 0x8e, 0xe9, 0xe7, 0x3a, 0x62, 0x0a, 0x57, 0x2a, 0x68, 0x5c, 0xfa, 0x15, 0xe1, 0xde, 0x29,
    0x92, 0xfc, 0x3c, 0x67, 0x3f, 0x53, 0xdc, 0xb5, 0x59, 0xad, 0x40, 0x21, 0xab, 0xc9, 0xba, 0x4e,
    0x8c, 0xaf, 0x73, 0x27, 0xfb, 0x3f, 0x87, 0x06, 0xe4, 0x05, 0xb9, 0x53, 0x05, 0x56, 0x58, 0x90,
    0x0c, 0xdb, 0x30, 0x60, 0x6c, 0x93, 0xff, 0x66, 0x51, 0x9b, 0xcc, 0x77, 0xec, 0x5b, 0x54, 0x06,
    0x36, 0x28, 0x2c, 0xc8, 0x11, 0x50, 0xf3, 0x2b, 0x4a, 0x12, 0x69, 0x99, 0x39, 0xa7, 0xb0, 0xc7,
    0xbd, 0xca, 0x54, 0x59, 0xed, 0xda, 0x81, 0x45, 0x95, 0xaf, 0x56, 0x4d, 0x9c, 0x84, 0xfb, 0x6e,
    0xf8, 0x3e, 0xa0, 0x37, 0x7b, 0x06, 0xa1, 0x41, 0xb0, 0xd4, 0x57, 0xbe, 0xc4, 0xa3, 0xdd, 0x4e,
    0x0d, 0x60, 0x17, 0x14, 0x75, 0x13, 0x1f, 0x6f, 0x26, 0x5f, 0xcc, 0xf4, 0xd2, 0xc8, 0x57, 0x03,
    0x15, 0xe7, 0x8d, 0xc2, 0x58, 0x3e, 0x74, 0xe1, 0x70, 0x62, 0x6a, 0xe0, 0xb4, 0x13, 0x97, 0x96,
    0x5a, 0x9b, 0x63, 0x03, 0x78, 0x82, 0xc6, 0x07, 0xd3, 0xbf, 0x90, 0x8e, 0x0d, 0x28, 0x45, 0xae,
    0x05, 0xcc, 0xd2, 0xb2, 0x4c, 0xc3, 0xf4, 0xdf, 0xc6, 0x3c, 0xd6, 0xe6, 0x16, 0xc9, 0x73, 0x40,
    0xf0, 0xa1, 0xce, 0xd1, 0xe5, 0x52, 0xf7, 0xc7, 0x91, 0x53, 0x3a, 0x61, 0xb8, 0xe4, 0x73, 0x94,
    0x63, 0x75, 0x24, 0x6c, 0x93, 0x56, 0x6a, 0xc3, 0xcc, 0x8f, 0x25, 0x02, 0xee, 0xaf, 0x4c, 0xba,
    0x65, 0x49, 0x51, 0x47, 0xab, 0x9e, 0x11, 0x19, 0xe4, 0x3c, 0x07, 0x5b, 0xea, 0x7b, 0xe7, 0xd7,
    0xf2, 0xcb, 0xad, 0xb6, 0xcd, 0xab, 0x6d, 0x21, 0x26, 0x1f, 0x0d, 0x9f, 0xce, 0x1d, 0xde, 0x48,
    0x14, 0xa0, 0xb8, 0xdc, 0x79, 0xd8, 0x19, 0x85, 0x24, 0x8a, 0xa6, 0xaf, 0xdc, 0xd9, 0xb8, 0xc0,
    0xf5, 0x31, 0x56, 0xb3, 0xb1, 0xcd, 0x91, 0xd0, 0x71, 0xaf, 0x7f, 0xd0, 0x33, 0x43, 0x6b, 0x75,
    0xc1, 0x94, 0x10, 0x29, 0x78, 0xa5, 0xfa, 0xce, 0xc1, 0x87, 0x76, 0x7f, 0x3d, 0x60, 0xd5, 0x6b,
    0x1f, 0x6c, 0xcf, 0x38, 0xdd, 0xb1, 0x2a, 0xbb, 0xb0, 0x10, 0xd3, 0x52, 0xd7, 0x6b, 0x82, 0x07,
    0x0a, 0x09, 0xdb, 0xd7, 0x8f, 0xac, 0x5d, 0xc1, 0x3e, 0x7e, 0x57, 0x0c, 0x2d, 0x02, 0xbe, 0xaf,
    0x5d, 0xc5, 0x06, 0x35, 0xb7, 0x80, 0x03, 0x4b, 0x82, 0x55, 0xfe, 0x6c, 0x1f, 0xf2, 0x73, 0xe8,
    0xd9, 0x69, 0x99, 0xe9, 0x5d, 0xab, 0xb4, 0xe4, 0xd0, 0x6f, 0x08, 0x24, 0x70, 0x8b, 0xf0, 0x70,
    0x1b, 0x5b, 0x20, 0x57, 0xd1, 0xb7, 0xf1, 0x8a, 0x09, 0x8f, 0xcd, 0x6d, 0xc2, 0x1f, 0xae, 0x00,
    0x16, 0x2f, 0x45, 0x75, 0xf1, 0x95, 0x0b, 0x7c, 0xf6, 0x75, 0xf4, 0xf2, 0x6b, 0x67, 0xe9, 0xc1,
    0xdf, 0x04, 0x4c, 0x87, 0x71, 0x09, 0x1a, 0x76, 0x58, 0xd8, 0x32, 0x81, 0x67, 0x0e, 0x44, 0xa0,
    0x45, 0x06, 0x7a, 0x38, 0xa3, 0x4d, 0xb9, 0xd2, 0xdf, 0xd3, 0x9b, 0x4f, 0xfa, 0xf0, 0xaf, 0xc9,
    0xee, 0xb3, 0xde, 0xe2, 0x45, 0x2e, 0x62, 0xb2, 0x5a, 0x3c, 0x74, 0x66, 0x34, 0x79, 0x76, 0xe9,
    0x80, 0xc4, 0xcd, 0x32, 0x5d, 0x60, 0x6a, 0x5c, 0xb8, 0x1d, 0x15, 0xbc, 0xba, 0xf0, 0x4e, 0x3d,
    0x66, 0x1e, 0x69, 0xf9, 0x9e, 0xe0, 0xbe, 0xc6, 0x95, 0xe6, 0x0b, 0xd5, 0xc4, 0x92, 0x23, 0x35,
    0x49, 0xe8, 0x13, 0x64, 0xd7, 0x79, 0x0b, 0xf1, 0xe1, 0x82, 0x37, 0x31, 0x3b, 0xef, 0xd1, 0x72,
    0x8f, 0xcb, 0x45, 0xea, 0x3d, 0x81, 0x1e, 0xde, 0xf2, 0x8e, 0x90, 0xc0, 0x0d, 0x19, 0x99, 0x78,
    0x87, 0x94, 0x8d, 0xe0, 0xc7, 0x1d, 0x56, 0x76, 0xae, 0x8c, 0x95, 0x5f, 0x89, 0x09, 0xe0, 0xa7,
    0x63, 0xfe, 0x18, 0x73, 0x1d, 0xf8, 0x25, 0xa4, 0x86, 0xb6, 0xe0, 0xf6, 0xb9, 0x86, 0xc7, 0x98,
    0xb2, 0xac, 0x37, 0x79, 0x69, 0x0e, 0xc3, 0x18, 0x75, 0xc1, 0xbf, 0x23, 0xfe, 0x9e, 0x1f, 0x40,
    0x04, 0x78, 0xd7, 0xf0, 0x43, 0x7f, 0x4b, 0x06, 0x5d, 0x43, 0xb8, 0xe0, 0xf8, 0xc3, 0xdc, 0x9c,
    0x02, 0x24, 0x91, 0x9e, 0xb4, 0x07, 0x70, 0x23, 0x2c, 0xdb, 0x09, 0x57, 0x0f, 0x33, 0xa1, 0x12,
    0xb6, 0xfd, 0x63, 0x00, 0x49, 0x86, 0xf8, 0x4c, 0xd3, 0x2a, 0xae, 0xd0, 0x4a, 0xa3, 0x9e, 0xf8,
    0x04, 0xfa, 0xd2, 0x91, 0xdf, 0x49, 0xa4, 0x05, 0x50, 0xd3, 0xf2, 0xcf, 0x5a, 0x38, 0x5a, 0x03,
    0x4f, 0x45, 0x07, 0x67, 0x21, 0x61, 0xdf, 0x30, 0xa0, 0xb1, 0xf0, 0x48, 0x07, 0x8b, 0x22, 0x54,
    0x93, 0x92, 0xf7, 0xdc, 0xe0, 0xa6, 0x17, 0x57, 0xf6, 0xda, 0xe9, 0x06, 0x60, 0x05, 0x53, 0x51,
    0x02, 0x00, 0xb6, 0x2d, 0xe6, 0xb1, 0xcd, 0x33, 0xe6, 0x7e, 0x1d, 0x80, 0x05, 0xc8, 0xc0, 0x0f,
    0xc1, 0xe3, 0x25, 0x21, 0x7a, 0x0d, 0x4e, 0x00, 0x6e, 0x64, 0xcc, 0x7e, 0x2a, 0x27, 0x84, 0xdb,
    0x3d, 0x94, 0x12, 0x84, 0xf8, 0x7e, 0x86, 0x1f, 0xa7, 0x02, 0xdb, 0x10, 0x2b, 0x1c, 0x28, 0x33,
    0x9d, 0x83, 0xc7, 0xf8, 0xbe, 0x49, 0xfb, 0x69, 0x53, 0xb2, 0xd1, 0x2d, 0x26, 0x8c, 0x1a, 0xe9,
    0xed, 0x32, 0xcd, 0x33, 0xf8, 0xa7, 0x34, 0xf6, 0xbf, 0xe0, 0xe3, 0x01, 0xd0, 0x34, 0x7c, 0x51,
    0x56, 0xbb, 0xa0, 0xa9, 0x07, 0x4b, 0x6e, 0xa1, 0xb3, 0xdd, 0x8e, 0xc2, 0x27, 0xd2, 0xbc, 0x08,
    0x8e, 0x45, 0x17, 0x85, 0x1f, 0xf8, 0xbc, 0x2a, 0x5d, 0x2c, 0xc6, 0x1d, 0xca, 0xa4, 0x15, 0x3a,
    0x61, 0xbc, 0xd8, 0xcf, 0x3e, 0x18, 0xd0, 0x43, 0x1d, 0x30, 0x2d, 0x81, 0x57, 0xaf, 0x74, 0xc3,
    0x0f, 0xea, 0x53, 0xc4, 0x0a, 0xfd, 0x19, 0x59, 0xd1, 0x7a, 0x1f, 0x36, 0x72, 0x6f, 0x6e, 0x6d,
    0x60, 0xff, 0xb8, 0x90, 0xd8, 0x28, 0x49, 0x08, 0x93, 0xc3, 0x4a, 0xb2, 0xc0, 0xdd, 0x03, 0x3c,
    0xf2, 0x95, 0x06, 0x96, 0xe9, 0x51, 0xc7, 0x2d, 0xc5, 0xe5, 0x68, 0x01, 0x18, 0x5f, 0x26, 0x8b,
    0x8a, 0x8f, 0xf9, 0x65, 0xd0, 0x74, 0x1b, 0xb3, 0xa8, 0x03, 0xac, 0x49, 0x00, 0xc0, 0x1a, 0x93,
    0x42, 0x15, 0x62, 0xfd, 0xbc, 0x95, 0x39, 0x44, 0x04, 0x32, 0x3f, 0x5e, 0xef, 0xfc, 0x44, 0x73,
    0x1b, 0x11, 0xe6, 0x9f, 0xf7, 0x06, 0xea, 0x97, 0xe7, 0xfb, 0x50, 0x8f, 0x15, 0x61, 0xa1, 0x16,
    0x6b, 0x32, 0xbf, 0x2b, 0xae, 0x0a, 0xcf, 0xd9, 0xa1, 0xce, 0xe0, 0xb3, 0xef, 0xd1, 0x23, 0x30,
    0x96, 0xc6, 0xf1, 0x9b, 0x0b, 0x03, 0xbd, 0x91, 0x2a, 0x7e, 0x2a, 0x48, 0xed, 0x73, 0x99, 0x87,
    0x77, 0x0f, 0x7f, 0x6c, 0x4f, 0xf0, 0x5c, 0xa7, 0x59, 0x75, 0x59, 0x06, 0x56, 0x6e, 0xe8, 0x45,
    0xdc, 0x2e, 0x03, 0x1a, 0xc7, 0x7e, 0x6e, 0x9e, 0x85, 0xd4, 0x98, 0x90, 0x17, 0xab, 0xe6, 0x13,
    0x85, 0x22, 0xa9, 0x5e, 0x94, 0xdf, 0x99, 0xf2, 0x84, 0x1f, 0x5c, 0x1e, 0xeb, 0xd8, 0xfa, 0x67,
    0xa4, 0x57, 0x12, 0x6f, 0x63, 0xd4, 0xd9, 0x4f, 0x5c, 0xaa, 0x4c, 0x07, 0x58, 0x7d, 0x58, 0xb9,
    0x60, 0x66, 0x9b, 0xb4, 0x99, 0x33, 0x43, 0x45, 0x34, 0x25, 0xc8, 0x15, 0xbb, 0x29, 0x0d, 0x65,
    0x5e, 0x97, 0x20, 0x93, 0x4b, 0xce, 0xb6, 0xff, 0xad, 0x40, 0xf6, 0xd1, 0x44, 0x79, 0xb7, 0xab,
    0xd3, 0x19, 0xfd, 0x4c, 0xa6, 0xa5, 0xff, 0x49, 0x2c, 0x84, 0x7b, 0xd3, 0xc6, 0xa7, 0xb7, 0x7d,
    0x98, 0xdf, 0x8f, 0x9b, 0x22, 0x38, 0xf9, 0x5f, 0xc1, 0xab, 0xf4, 0xcd, 0x55, 0xc4, 0xe9, 0x64,
    0x97, 0x7f, 0xd0, 0x81, 0x71, 0x33, 0xac, 0x08, 0x84, 0x92, 0x1f, 0x0a, 0xf2, 0xf5, 0x62, 0xb8,
    0x41, 0xac, 0xe8, 0xd5, 0x4f, 0xa5, 0x3a, 0x46, 0x73, 0x9f, 0x53, 0xff, 0x59, 0xbf, 0xea, 0x45,
    0x61, 0xdd, 0xe3, 0x00, 0x5c, 0xba, 0x5a, 0xf5, 0x08, 0x97, 0x14, 0xde, 0x83, 0x22, 0x8e, 0xc8,
    0x39, 0x3e, 0xaa, 0xd8, 0xf8, 0x8d, 0xcf, 0x79, 0xec, 0xe8, 0x72, 0xec, 0xb3, 0x2c, 0x25, 0xcc,
    0x75, 0xd8, 0x88, 0x31, 0x47, 0x4d, 0x95, 0xd2, 0x19, 0x8d, 0xb2, 0x77, 0xc4, 0xce, 0x9c, 0xc7,
    0x50, 0x29, 0xc9, 0x23, 0xdf, 0xae, 0x3a, 0xf5, 0xb6, 0xc4, 0x51, 0x6c, 0x3a, 0xc1, 0x04, 0xb3,
    0xe7, 0x96, 0x84, 0x50, 0xf0, 0xc2, 0x93, 0xb9, 0x6a, 0xa4, 0xcd, 0x7e, 0xa3, 0xc1, 0x2f, 0x8f,
    0xfa, 0x12, 0x24, 0x34, 0x28, 0x30, 0x7a, 0x39, 0x8d, 0x84, 0x43, 0x4a, 0x38, 0x45, 0x7f, 0xba,
    0x43, 0x6f, 0xfe, 0x0b, 0x41, 0xdf, 0xf8, 0x71, 0xcd, 0xdd, 0x2f, 0x63, 0x46, 0xfc, 0x0a, 0xe7,
    0x09, 0x00, 0xde, 0xa3, 0x8f, 0x4f, 0xc1, 0x0c, 0x41, 0xec, 0x16, 0xa4, 0xed, 0x1d, 0x84, 0x34,
    0x79, 0x0a, 0xb9, 0x09, 0x61, 0x9b, 0x4e, 0xea, 0xba, 0x47, 0xcd, 0xf4, 0xd6, 0x88, 0xb1, 0xc2,
    0x93, 0xd9, 0x5e, 0x62, 0xec, 0x0d, 0x0d, 0xf0, 0x57, 0x1b, 0xe9, 0xdc, 0x4d, 0x3f, 0x29, 0x26,
    0x45, 0x69, 0x02, 0x14, 0x15, 0xd0, 0x2b, 0x88, 0xd7, 0x18, 0x72, 0xc2, 0x73, 0x77, 0xdd, 0xd2,
    0x3d, 0x8b, 0x78, 0x23, 0xb2, 0xb0, 0xb3, 0x2f, 0xed, 0xa2, 0x5c, 0x36, 0xf3, 0xe3, 0x84, 0xd6,
    0x39, 0x29, 0x7f, 0xa2, 0x2a, 0x27, 0xb5, 0x03, 0x49, 0xc0, 0x36, 0x2c, 0x2c, 0x61, 0x67, 0xbf,
    0xcc, 0x15, 0x41, 0x39, 0x49, 0x51, 0x19, 0xec, 0xba, 0xfe, 0x19, 0xb8, 0x6e, 0x31, 0xb3, 0x5f,
    0x7e, 0x1b, 0xf1, 0xf9, 0x9d, 0xbf, 0x6a, 0xe1, 0xf9, 0x55, 0x67, 0xb0, 0x73, 0x5a, 0xde, 0x4f,
    0x57, 0x21, 0x0c, 0x9f, 0xe4, 0x54, 0xfc, 0xff, 0xc3, 0xb4, 0x2e, 0xbc, 0xa3, 0xfa, 0x96, 0x8e,
    0x8d, 0x87, 0x4b, 0x2b, 0x66, 0xce, 0x4a, 0xe2, 0x0f, 0xde, 0x34, 0xc3, 0xed, 0x7c, 0x16, 0x03,
    0x3b, 0xc1, 0xda, 0x7c, 0x50, 0xac, 0x3e, 0x89, 0xad, 0x98, 0x1a, 0x01, 0x00, 0x63, 0xf2, 0x57,
    0x75, 0x49, 0xc3, 0x85, 0x57, 0x16, 0x24, 0x17, 0x8e, 0xb2, 0x63, 0x08, 0xf8, 0x9b, 0x52, 0xf9,
    0x22, 0x70, 0xb0, 0x31, 0xe9, 0xa7, 0x67, 0xd7, 0xd6, 0x90, 0x38, 0xe8, 0x47, 0x7c, 0xb9, 0x4b,
    0x93, 0x33, 0x1a, 0xe6, 0xb5, 0x72, 0x58, 0x67, 0xc2, 0x33, 0x6e, 0xd9, 0xfe, 0x02, 0xcd, 0x5c,
    0xaf, 0x73, 0x9f, 0x83, 0x37, 0x19, 0xac, 0x55, 0x40, 0xa0, 0x76, 0x3a, 0xe3, 0x40, 0x2a, 0x4a,
    0x67, 0xd7, 0x0a, 0xc6, 0xfa, 0xd7, 0xf1, 0x43, 0xe8, 0xe3, 0x29, 0x35, 0xdb, 0x6e, 0x1d, 0x4c,
    0x09, 0xd0, 0x12, 0x5f, 0x9b, 0xb8, 0xe8, 0x5a, 0x1c, 0x15, 0xfa, 0x78, 0x6f, 0x7b, 0xab, 0x7c,
    0x91, 0x7b, 0x41, 0xa3, 0xb1, 0x4c, 0x11, 0xea, 0x3c, 0x22, 0xc9, 0x7c, 0xe6, 0xd8, 0xff, 0x3e,
    0x2d, 0x54, 0x4d, 0xf8, 0x4d, 0x7d, 0x06, 0xfd, 0x77, 0xf5, 0x51, 0x89, 0x36, 0xeb, 0xbe, 0xf7,
    0xad, 0x69, 0xc8, 0x69, 0xf6, 0x6f, 0x3b, 0xfa, 0xba, 0xf8, 0x14, 0x82, 0xf1, 0x46, 0x60, 0xcc,
    0x2a, 0xc8, 0x80, 0x5a, 0xd4, 0x40, 0xbb, 0x50, 0x82, 0x4a, 0x1b, 0x47, 0x08, 0xc2, 0x5d, 0x36,
    0xff, 0x5e, 0x52, 0x06, 0x4b, 0x8e, 0x78, 0xb9, 0x90, 0x10, 0xe3, 0xa5, 0xf9, 0x58, 0x32, 0x97,
    0xd8, 0x93, 0x08, 0x87, 0x4f, 0xf5, 0x8a, 0x05, 0x6f, 0x6c, 0x60, 0xa9, 0x0a, 0x97, 0xbd, 0x35,
    0x70, 0xc0, 0x3b, 0x6f, 0x2c, 0x08, 0x13, 0xe0, 0xaa, 0x7b, 0xdf, 0xdf, 0x2f, 0x88, 0x73, 0xab,
    0x67, 0x8b, 0xdc, 0xfa, 0x6f, 0xf2, 0x6b, 0x4a, 0xa6, 0x72, 0xb3, 0x17, 0x81, 0x12, 0x7c, 0x23,
    0xdc, 0xa1, 0xd9, 0x34, 0x64, 0xd2, 0x90, 0x5a, 0x0c, 0xa6, 0xb2, 0x42, 0x9d, 0xb5, 0x43, 0xd7,
    0x43, 0xcb, 0xc4, 0x5c, 0x39, 0x37, 0x5e, 0x6a, 0xf6, 0xf9, 0x8d, 0x6c, 0x98, 0xa9, 0xae, 0x24,
    0xa8, 0x0b, 0xa7, 0xc5, 0x9f, 0x93, 0xa0, 0x7e, 0x19, 0xef, 0x8b, 0x96, 0xac, 0x8b, 0x0b, 0x2c,
    0xfa, 0xf5, 0xfe, 0xd0, 0xaf, 0xad, 0xb9, 0x95, 0x3f, 0x34, 0xe3, 0xad, 0xe4, 0xf6, 0xd7, 0x0a,
    0xdf, 0xc9, 0xef, 0x36, 0x97, 0xd2, 0x12, 0x2c, 0x23, 0x0a, 0x3b, 0x34, 0xdd, 0x2b, 0x06, 0xe5,
    0xfe, 0x3e, 0x55, 0xf3, 0xcb, 0xf2, 0x95, 0xda, 0x70, 0xb7, 0xf3, 0x16, 0x78, 0x92, 0xca, 0xa1,
    0xb2, 0xd6, 0xf7, 0x0c, 0x7c, 0xcb, 0xca, 0x82, 0x53, 0x21, 0x32, 0x0d, 0x0d, 0x0d, 0xf7, 0xee,
    0x02, 0x0a, 0x47, 0xd8, 0x25, 0x5c, 0x49, 0x73, 0x18, 0x45, 0x3a, 0x8d, 0xeb, 0x2c, 0xd2, 0x9e,
    0xef, 0x76, 0x41, 0x4d, 0xc8, 0xe8, 0x81, 0x55, 0xfc, 0xd6, 0xf4, 0xf6, 0xa5, 0x14, 0xb1, 0x40,
    0xc9, 0x08, 0x0d, 0xea, 0x04, 0xeb, 0xaf, 0x23, 0x5e, 0xe9, 0x28, 0x7b, 0x8a, 0x7c, 0x06, 0x4f,
    0x71, 0x74, 0xc1, 0x66, 0x24, 0xa2, 0x73, 0xfc, 0xae, 0xf5, 0xf3, 0xde, 0x53, 0x9f, 0xdb, 0x3e,
    0x9b, 0xbe, 0x62, 0xe2, 0x58, 0x32, 0x13, 0x1c, 0xa7, 0x0d, 0xff, 0xb2, 0x93, 0x58, 0xcf, 0xff,
    0x2a, 0x26, 0x48, 0x2c, 0x10, 0x82, 0x61, 0x1a, 0x93, 0x93, 0x8d, 0x5c, 0xf2, 0xa7, 0xb8, 0x8e,
    0x78, 0x85, 0xce, 0xe5, 0x39, 0x44, 0x9a, 0xec, 0xcc, 0x82, 0x35, 0xc8, 0x30, 0x77, 0x3d, 0x87,
    0x6d, 0xb0, 0x0a, 0xa5, 0xf6, 0xe6, 0x41, 0xc5, 0x53, 0x27, 0x88, 0xe4, 0xab, 0x4a, 0xfd, 0x80,
    0xd5, 0x8e, 0xa1, 0xe0, 0x3c, 0x03, 0xfc, 0x36, 0x73, 0x3b, 0x5c, 0x17, 0xb1, 0x77, 0x68, 0xdd,
    0x7c, 0xbb, 0xf2, 0x49, 0xcc, 0x9e, 0x89, 0x1c, 0xc1, 0xbb, 0x03, 0x7c, 0xea, 0x98, 0x75, 0xed,
    0xc7, 0x42, 0x56, 0x68, 0x15, 0xa4, 0xe8, 0x98, 0xd9, 0x1f, 0x13, 0xaa, 0xb8, 0xfb, 0x15, 0x0f,
    0x94, 0x97, 0x03, 0x92, 0xbf, 0x38, 0x70, 0xdf, 0xde, 0xf1, 0x00, 0xfe, 0xf0, 0x6c, 0xb8, 0x35,
    0x19, 0x6a, 0xb3, 0xad, 0xe2, 0x93, 0xd9, 0x9e, 0x93, 0x9e, 0x8a, 0x21, 0x22, 0x5a, 0x4a, 0x14,
    0x80, 0x71, 0x40, 0x3f, 0x5a, 0xfc, 0x81, 0xf1, 0x8e, 0x47, 0xc6, 0x29, 0xe2, 0x4c, 0x7a, 0xca,
    0xcd, 0x00, 0x67, 0x7d, 0xe7, 0x34, 0xab, 0x8a, 0x4a, 0xea, 0xef, 0xc3, 0xc0, 0xe1, 0xf5, 0x0c,
    0xb8, 0x08, 0xbe, 0x59, 0x44, 0x56, 0x86, 0x59, 0x0e, 0x65, 0xe6, 0x93, 0x9a, 0xf6, 0xda, 0x0f,
    0x90, 0x7c, 0xb7, 0x95, 0xc1, 0x70, 0x1d, 0x8c, 0xc5, 0x7a, 0xe8, 0xd2, 0x1e, 0x30, 0xfa, 0xe0,
    0x30, 0x15, 0xbc, 0x22, 0x2d, 0x2c, 0x14, 0x90, 0xb8, 0x8e, 0x6b, 0xfe, 0x37, 0x78, 0x74, 0x7e,
    0x1c, 0xdb, 0x87, 0xd7, 0xa7, 0x1d, 0x09, 0xf3, 0x5a, 0xd4, 0x0f, 0x69, 0x59, 0x91, 0x98, 0xa5,
    0xeb, 0xa6, 0x70, 0xc2, 0xb5, 0x1f, 0xf9, 0xbd, 0xa4, 0xf2, 0xd0, 0xe4, 0x7a, 0x55, 0xb8, 0x32,
    0xeb, 0xb7, 0x3b, 0xf8, 0x03, 0x8a, 0xc7, 0xe4, 0x96, 0xd5, 0x04, 0x4c, 0xd7, 0x26, 0x91, 0xf6,
    0xf0, 0xce, 0xe7, 0x4e, 0x7e, 0x46, 0xb4, 0x59, 0x54, 0x12, 0xb0, 0xa0, 0x29, 0xb1, 0xf1, 0xd5,
    0x29, 0x22, 0xb1, 0x9f, 0xae, 0x9c, 0xf0, 0xc2, 0xe0, 0xad, 0xd6, 0xdc, 0x47, 0xcb, 0x01, 0xac,
    0x62, 0x2a, 0x0b, 0x71, 0x11, 0x9c, 0x33, 0x9e, 0xf0, 0xc3, 0x1f, 0x83, 0x9e, 0x83, 0x14, 0x97,
    0x7e, 0xeb, 0x06, 0x74, 0x18, 0xb0, 0x28, 0x78, 0x61, 0x4b, 0x2d, 0x48, 0x71, 0xda, 0xc1, 0x56,
    0x3e, 0x16, 0x8a, 0x15, 0xe5, 0xb2, 0xae, 0xf7, 0xb7, 0x76, 0xab, 0xb6, 0xc3, 0xf2, 0x55, 0x6a,
    0x8d, 0x77, 0x92, 0xd7, 0xb2, 0xaf, 0xe3, 0x61, 0xdd, 0x5b, 0xcf, 0x2b, 0x2b, 0x9f, 0xdf, 0x06,
    0x2e, 0x1d, 0x8c, 0xd3, 0x0e, 0x26, 0x4b, 0x77, 0x8c, 0x10, 0x82, 0x60, 0xdc, 0xaa, 0xd8, 0x12,
    0xd0, 0xb7, 0xd7, 0xfa, 0x3d, 0xbc, 0x82, 0xa6, 0x1f, 0x21, 0xda, 0xe7, 0x7a, 0x31, 0xe2, 0x00,
    0x3a, 0x98, 0xb0, 0xa4, 0x7d, 0xa2, 0x89, 0x11, 0xbb, 0xa7, 0x3d, 0xd8, 0xf0, 0x54, 0xb2, 0x15,
    0xe8, 0x92, 0x7a, 0x27, 0x7f, 0x30, 0xb1, 0x7c, 0x17, 0x35, 0xa2, 0xf0, 0x1a, 0xdd, 0x23, 0xa9,
    0x7e, 0x24, 0x9f, 0xe6, 0x19, 0x90, 0x57, 0x9b, 0x77, 0x3d, 0xb9, 0x22, 0x01, 0x26, 0x58, 0x53,
    0xd0, 0x67, 0xe6, 0x4a, 0x2d, 0x80, 0x15, 0x83, 0x85, 0xe5, 0xe9, 0xa3, 0x76, 0xe5, 0x5d, 0x08,
    0x7b, 0xe8, 0xce, 0xad, 0x95, 0xc5, 0x2c, 0xf6, 0xca, 0xd9, 0xd6, 0xd7, 0xa9, 0xa8, 0xae, 0x53,
    0xc6, 0x06, 0xd3, 0x9b, 0x2d, 0x33, 0x8b, 0xed, 0xb2, 0x14, 0x0c, 0xf9, 0x20, 0x33, 0x24, 0xcd,
    0x99, 0x6d, 0x28, 0xdf, 0xd0, 0xb6, 0x6a, 0x69, 0xa6, 0x87, 0xdb, 0x49, 0x49, 0xe5, 0x06, 0x6e,
    0x08, 0x9b, 0x1c, 0x2a, 0x00, 0x08, 0x54, 0xa4, 0xc6, 0xb5, 0x87, 0x91, 0xdd, 0x72, 0x6a, 0xd4,
    0xaf, 0x85, 0xc9, 0x2a, 0xec, 0xb9, 0x73, 0xe9, 0x83, 0x53, 0xb5, 0xd2, 0xb0, 0x8a, 0xeb, 0x66,
    0xb7, 0x2c, 0x79, 0x7c, 0x4f, 0x83, 0x60, 0xb7, 0x61, 0x02, 0x6e, 0x38, 0x58, 0x9b, 0xe6, 0x04,
    0xc1, 0xf9, 0x70, 0xfd, 0x59, 0xfe, 0x3c, 0xad, 0x6a, 0x45, 0x2a, 0xf2, 0x78, 0x38, 0x3a, 0x04,
    0x75, 0x6a, 0x76, 0xcb, 0x6b, 0x60, 0x83, 0x54, 0x97, 0x81, 0x34, 0x5a, 0x7f, 0xb5, 0x82, 0x47,
    0x9f, 0x51, 0x14, 0x3f, 0x90, 0xe5, 0xa5, 0x7e, 0x33, 0x6e, 0x03, 0x40, 0x0e, 0x8c, 0x9a, 0xbe,
    0x0a, 0x4e, 0x8e, 0xe4, 0x67, 0x92, 0x79, 0xab, 0xdd, 0xbf, 0x06, 0xc4, 0xbe, 0x20, 0x41, 0x0c,
    0x52, 0x2d, 0x19, 0xb0, 0xe7, 0x50, 0xe4, 0xe0, 0x29, 0xb7, 0xfd, 0x0c, 0x9a, 0x6c, 0x24, 0xca,
    0xe8, 0x4a, 0x9a, 0x66, 0x5e, 0xaa, 0xf3, 0x52, 0x4b, 0xa4, 0xf3, 0x4c, 0x29, 0xdc, 0xdb, 0x2d,
    0xd2, 0x5d, 0x71, 0x0a, 0x08, 0xc0, 0x22, 0x8e, 0xe2, 0x96, 0xf0, 0xd6, 0x9b, 0xa1, 0xa9, 0x77,
    0x8a, 0x2e, 0x57, 0xd7, 0x28, 0x32, 0xf9, 0x87, 0xbd, 0x48, 0xf7, 0xce, 0xea, 0x27, 0x45, 0x03,
    0x9f, 0x5f, 0xf5, 0x03, 0x2b, 0x7b, 0x1c, 0xdd, 0x0e, 0xb6, 0x63, 0x03, 0xb6, 0x88, 0x37, 0xa6,
    0xcc, 0xa9, 0xbf, 0x40, 0x9d, 0x72, 0xff, 0xa6, 0x8e, 0xf8, 0xaa, 0x53, 0xb5, 0x3b, 0x21, 0x5d,
    0x99, 0xca, 0x6a, 0x1c, 0x3f, 0xce, 0xa8, 0xb5, 0xbe, 0x1a, 0x4a, 0x40, 0xb4, 0xc7, 0x99, 0xd2,
    0xdc, 0x65, 0xcd, 0xb2, 0xb4, 0x32, 0xe0, 0xca, 0x7a, 0x16, 0x24, 0xbc, 0x1e, 0x20, 0xd5, 0x50,
    0x56, 0x3c, 0x71, 0x99, 0x2d, 0x41, 0x37, 0xd2, 0x5a, 0x8b, 0x46, 0x72, 0x83, 0x0a, 0x07, 0x29,
    0x10, 0xab, 0xf6, 0xf5, 0xc2, 0x51, 0x29, 0x27, 0x7f, 0x33, 0x64, 0x9f, 0x26, 0x32, 0x9f, 0x5c,
    0x37, 0x9b, 0x99, 0x0f, 0x42, 0xad, 0x9e, 0xe1, 0x53, 0x0e, 0xb1, 0xb6, 0x41, 0xcb, 0x28, 0x50,
    0x17, 0x38, 0xd6, 0x3e, 0x28, 0xdf, 0x6a, 0x50, 0x4b, 0x5d, 0x97, 0x11, 0xe7, 0x33, 0x82, 0xa6,
    0x5f, 0xe7, 0xf1, 0x9b, 0x85, 0x1f, 0x85, 0xe8, 0xe8, 0xe1, 0x0d, 0x7a, 0xdf, 0x44, 0xe1, 0x72,
    0xac, 0x3a, 0x3d, 0x9c, 0xb2, 0x33, 0xf4, 0x40, 0xb9, 0xa8, 0xd3, 0xdf, 0x9e, 0xc8, 0x92, 0xdf,
    0x92, 0x3d, 0xdc, 0xd6, 0x72, 0x7d, 0x54, 0xf4, 0x2d, 0x46, 0xf1, 0x3e, 0xba, 0xfd, 0x06, 0x57,
    0xeb, 0x24, 0x84, 0xd4, 0x7e, 0x2d, 0x70, 0xfd, 0x45, 0xcf, 0x93, 0x2e, 0xa9, 0x19, 0xc7, 0x62,
    0x58, 0xde, 0x91, 0x82, 0x04, 0x2a, 0x86, 0x13, 0x73, 0x8c, 0xd8, 0xbe, 0xd0, 0x9c, 0xb6, 0xe3,
    0x2a, 0x68, 0x73, 0xaa, 0x8c, 0x38, 0x4a, 0x01, 0x27, 0x0b, 0xef, 0x6a, 0x6f, 0x93, 0x3c, 0xc0,
    0xca, 0x4a, 0x06, 0x2f, 0xea, 0x07, 0x2d, 0x9f, 0x2a, 0xe2, 0xe3, 0xb0, 0x18, 0xee, 0x55, 0x90,
    0x60, 0x19, 0xdb, 0xd5, 0xf4, 0x4c, 0x92, 0xaa, 0x7d, 0xef, 0x1e, 0x08, 0xbf, 0x19, 0x8e, 0xb1,
    0xc9, 0xf0, 0x1f, 0xec, 0xea, 0x09, 0x77, 0x5d, 0xae, 0xff, 0x52, 0xd1, 0x52, 0x96, 0xe6, 0x0a,
    0x1b, 0x5b, 0xf7, 0xb2, 0x32, 0x82, 0x6e, 0x12, 0xf2, 0x8b, 0x76, 0xa1, 0xa5, 0xd7, 0xd2, 0xec,
    0x5c, 0xbd, 0xa8, 0x2a, 0x82, 0x96, 0xa4, 0x65, 0xa8, 0xf6, 0x18, 0x23, 0xe9, 0x43, 0x2a, 0x8c,
    0xc5, 0x6a, 0x98, 0x22, 0xc8, 0x2f, 0x4a, 0x7c, 0xd6, 0xe3, 0x70, 0x14, 0xab, 0x48, 0xe6, 0x48,
    0x92, 0x93, 0x18, 0x6d, 0xf5, 0x80, 0xab, 0xca, 0x1d, 0xdb, 0x7c, 0xb3, 0x9d, 0xca, 0x46, 0x8e,
    0x2f, 0x85, 0x32, 0x12, 0xb4, 0x09, 0xa9, 0x2a, 0x61, 0x11, 0x74, 0xca, 0x98, 0x30, 0x36, 0x7b,
    0x4d, 0x34, 0x9a, 0x79, 0x6d, 0xc2, 0x4a, 0xa8, 0x3b, 0xe5, 0xce, 0x9e, 0x22, 0x33, 0x9c, 0xaf,
    0x59, 0xf9, 0xce, 0x43, 0x4c, 0x77, 0xee, 0xe0, 0xd8, 0x87, 0x0a, 0xbe, 0xff, 0x46, 0x94, 0x60,
    0x0a, 0x70, 0xd0, 0x5f, 0x7c, 0xcd, 0x74, 0xba, 0xb7, 0xd5, 0x60, 0xab, 0xdb, 0x8b, 0xea, 0xb7,
    0x96, 0xa4, 0x87, 0x40, 0x13, 0x46, 0xc2, 0x0e, 0x99, 0x6a, 0x12, 0xb4, 0xfe, 0xff, 0xea, 0xa2,
    0x9d, 0x38, 0xc7, 0xb1, 0xed, 0x46, 0x62, 0xfc, 0x22, 0xe5, 0xe5, 0x0b, 0xad, 0x2f, 0xee, 0xbe,
    0x4e, 0x89, 0xde, 0x11, 0x19, 0xf4, 0xe9, 0x5e, 0x1a, 0x5a, 0x78, 0x3f, 0xab, 0x36, 0xa8, 0xe2,
    0xf9, 0x83, 0xd8, 0x0a, 0xee, 0xf4, 0x74, 0x1c, 0xdb, 0xb9, 0x24, 0xdf, 0x5e, 0xbd, 0x58, 0x2d,
    0x0a, 0xd6, 0xfc, 0x3d, 0x4e, 0x5b, 0x5f, 0xcb, 0x64, 0x0f, 0x46, 0xdc, 0x61, 0xf2, 0x92, 0x77,
    0x65, 0xd1, 0x21, 0xe6, 0xbb, 0x76, 0x56, 0xe5, 0x05, 0x7a, 0xd8, 0x8d, 0x58, 0x7c, 0xbf, 0x04,
    0x48, 0x8f, 0x35, 0x41, 0x5a, 0x17, 0x4d, 0xee, 0xc6, 0x9a, 0xfd, 0xb2, 0x60, 0xd5, 0x9c, 0xff,
    0x6d, 0xc6, 0x18, 0x20, 0xa7, 0xbd, 0xea, 0x33, 0xb6, 0xe5, 0x9d, 0xcd, 0xc0, 0xff, 0xe8, 0x6d,
    0x7c, 0x6e, 0xc8, 0xb3, 0xf9, 0x46, 0xbb, 0xfd, 0xbf, 0xc8, 0x86, 0x28, 0xd3, 0x84, 0xe0, 0xae,
    0xc0, 0x5b, 0x9b, 0x35, 0xc0, 0xb9, 0x27, 0x81, 0x71, 0x59, 0xb3, 0x99, 0x4f, 0x0f, 0x9e, 0xa9,
    0x24, 0x4f, 0xe6, 0xaa, 0x91, 0x2d, 0xde, 0xb2, 0xef, 0xcf, 0xc2, 0x0c, 0x01, 0xe5, 0x59, 0xa4,
    0x87, 0x42, 0x1e, 0x90, 0x60, 0xcb, 0x10, 0x2d, 0x9f, 0x5d, 0xdf, 0x97, 0x8d, 0xbc, 0x24, 0x35,
    0x29, 0xa2, 0x66, 0xec, 0x6f, 0x51, 0xb2, 0xd7, 0x08, 0x0d, 0x5b, 0xde, 0x96, 0xba, 0xce, 0x9f,
    0x4c, 0x96, 0x7b, 0xa5, 0x35, 0xc1, 0xf0, 0x98, 0xb1, 0x50, 0xe3, 0x4a, 0x86, 0x57, 0xf1, 0x4e,
    0x6b, 0x58, 0x44, 0x66, 0x87, 0x95, 0xca, 0x51, 0xc6, 0x7c, 0xfd, 0x3b, 0x01, 0x00, 0xba, 0xe8,
    0xdc, 0xeb, 0x85, 0xc2, 0x06, 0x22, 0x7b, 0xa2, 0xb9, 0x5b, 0xc2, 0xea, 0xaf, 0x55, 0x65, 0x4f,
    0xf2, 0x38, 0xc1, 0xc5, 0x7f, 0xee, 0x60, 0x16, 0xef, 0x56, 0x1e, 0xd0, 0x29, 0x45, 0x83, 0xd6,
    0xcf, 0x7e, 0x26, 0xdc, 0x20, 0x9b, 0x08, 0x78, 0xc4, 0x2e, 0xb7, 0x0f, 0x98, 0x5d, 0x9a, 0x1c,
    0x5f, 0xdb, 0xe6, 0xb9, 0x86, 0xf0, 0x4f, 0x2c, 0x1a, 0xeb, 0xd2, 0xb6, 0x4f, 0xd9, 0xb2, 0xa6,
    0x7b, 0x11, 0x18, 0x24, 0xa2, 0xf1, 0x1a, 0xfc, 0xdd, 0xf6, 0xc5, 0xfe, 0x2b, 0x9b, 0x6a, 0x41,
    0xe9, 0x00, 0x2b, 0xd6, 0x29, 0x64, 0x54, 0xa3, 0x55, 0xe7, 0x9b, 0xb4, 0x26, 0x90, 0x5a, 0xb1,
    0xee, 0x06, 0xb8, 0x9d, 0x3e, 0x7d, 0x6c, 0x9d, 0x6f, 0x51, 0x75, 0xd1, 0x5e, 0x0c, 0xf5, 0x60,
    0xa2, 0xe9, 0x1a, 0x46, 0xbe, 0x3f, 0x2d, 0x40, 0x60, 0xa3, 0x8e, 0x0f, 0x74, 0x4d, 0x6e, 0xa2,
    0xf2, 0x10, 0x7b, 0x3c, 0xcd, 0x44, 0x10, 0xb1, 0x68, 0x8e, 0x69, 0x45, 0xee, 0x70, 0x98, 0x82,
    0xcd, 0xf3, 0x5e, 0x65, 0x36, 0x1f, 0x2f, 0xc7, 0x83, 0xf5, 0x63, 0xa8, 0xb3, 0xcf, 0xb0, 0x4f,
    0xfb, 0x34, 0xe6, 0xca, 0x14, 0x4e, 0x7b, 0x25, 0x94, 0xc3, 0x6c, 0x88, 0x86, 0x8e, 0xe4, 0x22,
    0x10, 0x49, 0x63, 0x4a, 0xc7, 0xf5, 0x37, 0x5a, 0x30, 0x53, 0x37, 0xa2, 0xaf, 0xf8, 0x28, 0xad,
    0x3c, 0x04, 0x63, 0x2a, 0xe8, 0x9e, 0x71, 0xb4, 0x1e, 0x49, 0x55, 0x8c, 0x7d, 0xed, 0x7d, 0xe4,
    0x2d, 0x0e, 0x56, 0xcc, 0xfc, 0x76, 0x52, 0xe5, 0xb0, 0xa4, 0xd8, 0x26, 0x1f, 0xa4, 0xfa, 0x58,
    0xa2, 0x4d, 0xf5, 0xa1, 0x14, 0xc4, 0xa5, 0xb8, 0xf1, 0x8b, 0x78, 0xc6, 0x2d, 0xdb, 0x05, 0xf2,
    0x52, 0x8e, 0xdb, 0x0e, 0x43, 0xc9, 0x45, 0x98, 0x45, 0xf8, 0x2c, 0xa2, 0x92, 0xeb, 0x68, 0xeb,
    0x1f, 0x1e, 0x96, 0x41, 0xb5, 0x06, 0x3c, 0x5c, 0xeb, 0xfe, 0x73, 0x38, 0x56, 0xcb, 0x92, 0x0d,
    0x68, 0x17, 0xd5, 0xce, 0x74, 0x86, 0xc0, 0xc2, 0x77, 0x02, 0xde, 0xd5, 0x23, 0x64, 0x37, 0xe1,
    0xc8, 0x54, 0xf1, 0x25, 0xc2, 0x23, 0xf5, 0x6e, 0x06, 0x44, 0x0b, 0xfa, 0xd9, 0x82, 0x85, 0x19,
    0xdb, 0x54, 0xb9, 0xb3, 0xdc, 0x6d, 0xd8, 0xbe, 0x94, 0xd7, 0xbb, 0x57, 0x4c, 0x05, 0x83, 0xe2,
    0x41, 0x13, 0x88, 0x2f, 0x65, 0x12, 0x7f, 0xd1, 0xb3, 0x83, 0xb4, 0xc6, 0x48, 0x5c, 0x63, 0x90,
    0xff, 0xbd, 0x5b, 0x7a, 0x55, 0xa0, 0x66, 0xb6, 0x68, 0xc4, 0x96, 0xe7, 0xed, 0xad, 0x30, 0x85,
    0xef, 0x26, 0x20, 0x8d, 0x98, 0x23, 0xaf, 0xde, 0xab, 0x27, 0x3c, 0x96, 0x5a, 0x0c, 0x79, 0x12,
    0x7a, 0xda, 0x6e, 0xf4, 0x7f, 0x8c, 0xeb, 0x3c, 0x5a, 0x7b, 0x3a, 0x97, 0x4c, 0x23, 0xb1, 0xd5,
    0x0c, 0x3f, 0x78, 0x6a, 0x5a, 0xb6, 0xf3, 0x2f, 0x12, 0xe0, 0x90, 0x8e, 0xda, 0xbe, 0x2a, 0x2a,
};
