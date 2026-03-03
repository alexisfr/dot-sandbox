const std = @import("std");

const YELLOW = "\x1b[1;33m";
const RESET = "\x1b[0m";

/// Simple progress bar printed to stderr.
/// Call `update(current, total, detail)` repeatedly, then `finish()`.
pub const ProgressBar = struct {
    step: []const u8,
    width: usize = 20,

    pub fn update(self: ProgressBar, current: u64, total: u64, detail: []const u8) void {
        const pct: u64 = if (total > 0) @min(current * 100 / total, 100) else 0;
        const filled: usize = if (total > 0) @intCast(@min(pct * self.width / 100, self.width)) else 0;
        const empty = self.width - filled;

        std.debug.print("\r📥 {s:<22} {s}[", .{ self.step, YELLOW });
        var i: usize = 0;
        while (i < filled) : (i += 1) std.debug.print("█", .{});
        i = 0;
        while (i < empty) : (i += 1) std.debug.print("░", .{});
        std.debug.print("]{s} {d}% {s}", .{ RESET, pct, detail });
    }

    pub fn finish(self: ProgressBar, detail: []const u8) void {
        _ = self;
        std.debug.print("\r{s:<60}\r", .{" "}); // clear line
        _ = detail;
    }
};
