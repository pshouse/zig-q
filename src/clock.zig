const std = @import("std");

pub const Clock = struct {
    ticks: u64 = 0,
    time_of_day: f64 = 0,
    seconds_per_day: f64,
    update_rate: f64,
    time_multiplier: f64,

    pub fn init(time: f64, seconds_per_day: f64, update_rate: f64, time_multiplier: f64) Clock {
        return .{
            .ticks = 0,
            .time_of_day = time,
            .seconds_per_day = seconds_per_day,
            .update_rate = update_rate,
            .time_multiplier = time_multiplier,
        };
    }

    pub fn tick(self: *Clock) void {
        self.ticks += 1;
        self.time_of_day += ((1.0 + self.update_rate) / self.seconds_per_day) * self.time_multiplier;
        if (self.time_of_day > 1.0) self.time_of_day = 0;
    }
};

test "clock tick increments" {
    var c = Clock.init(0.0, 120.0, 5.0, 1.0);
    c.tick();
    try std.testing.expectEqual(@as(u64, 1), c.ticks);
}