const std = @import("std");
const output = @import("output.zig");

/// Minimum milliseconds between redraws. Prevents flickering on fast connections.
const REDRAW_INTERVAL_MS: i64 = 50; // 20 fps max

/// Simple in-place progress bar printed to stderr using \r.
/// Call `update(current, total, detail)` each chunk, then `finish()` when done.
///
/// finish() is also called automatically from update() the moment current >= total,
/// so the bar locks in place immediately at download completion.
pub const ProgressBar = struct {
    step: []const u8,
    width: usize = 20,
    /// Tracked by update(); used by finish() to format the final size.
    bytes_done: u64 = 0,
    bytes_total: ?u64 = null,
    /// Set by finish() to make it idempotent.
    finished: bool = false,
    /// Set to true once renderBar() has drawn at least one frame.
    rendered: bool = false,
    /// Timestamp (ms) of last redraw, for rate limiting.
    last_draw_ms: i64 = 0,

    pub fn update(self: *ProgressBar, current: u64, total: ?u64, detail: []const u8) void {
        if (self.finished) return;

        self.bytes_done = current;
        self.bytes_total = total;

        const mode = output.getRenderMode();
        if (mode == .rich or mode == .plain) {
            const now = std.time.milliTimestamp();
            const at_100 = if (total) |t| current >= t else false;
            // Always draw at 100%; otherwise throttle to REDRAW_INTERVAL_MS.
            if (at_100 or now - self.last_draw_ms >= REDRAW_INTERVAL_MS) {
                self.last_draw_ms = now;
                renderBar(self, current, total, detail);
            }
        }

        // Auto-complete as soon as download reaches 100%.
        if (total) |t| {
            if (current >= t) self.finish();
        }
    }

    /// Build and write the entire bar as a single string to avoid partial-frame glitches.
    fn renderBar(self: *ProgressBar, current: u64, total: ?u64, detail: []const u8) void {
        self.rendered = true;
        const mode = output.getRenderMode();
        const fill: []const u8 = if (mode == .rich) "█" else "=";
        const empty_ch: []const u8 = if (mode == .rich) "░" else " ";
        const prefix: []const u8 = if (mode == .rich) "📥" else "[DL]";

        // Build the complete bar line into a stack buffer, then write it in one shot.
        // Prefix with \r to return to column 0; in rich mode also erase to end-of-line
        // (\x1b[2K) so that when done_str shrinks (e.g. KB→MB transition) no stale
        // characters remain visible.
        var buf: [512]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const w = fbs.writer();

        const line_start: []const u8 = if (mode == .rich) "\r\x1b[2K" else "\r";

        if (total) |t| {
            const pct: u64 = if (t > 0) @min(current * 100 / t, 100) else 0;
            const filled: usize = @intCast(@min(pct * self.width / 100, self.width));
            const n_empty = self.width - filled;

            var done_buf: [32]u8 = undefined;
            var total_buf: [32]u8 = undefined;
            const done_str = fmtBytes(current, &done_buf);
            const total_str = fmtBytes(t, &total_buf);

            const is_done = current >= t;
            const status_sym = if (is_done) output.SYM_OK else output.SYM_ARROW;
            const status_color = if (is_done) output.GREEN else output.YELLOW;

            w.print("{s}{s} {s}{s:<14}{s} [{s}{s}{s}] [", .{
                line_start, prefix, output.CYAN, self.step, output.RESET,
                status_color, status_sym, output.RESET,
            }) catch return;
            for (0..filled) |_| w.writeAll(fill) catch return;
            for (0..n_empty) |_| w.writeAll(empty_ch) catch return;
            w.print("] {d:3}%  {s} / {s}{s}", .{ pct, done_str, total_str, detail }) catch return;
        } else {
            var done_buf: [32]u8 = undefined;
            const done_str = fmtBytes(current, &done_buf);

            w.print("{s}{s} {s}{s:<14}{s} [{s}{s}{s}] [", .{
                line_start, prefix, output.CYAN, self.step, output.RESET,
                output.YELLOW, output.SYM_ARROW, output.RESET,
            }) catch return;
            for (0..self.width) |_| w.writeAll(fill) catch return;
            w.print("]  --   {s}{s}", .{ done_str, detail }) catch return;
        }

        std.debug.print("{s}", .{fbs.getWritten()});
    }

    /// Lock the bar in place and move to the next line so subsequent output
    /// doesn't overwrite it. In pipe mode, prints a step line instead.
    /// Safe to call multiple times — only acts on the first call.
    pub fn finish(self: *ProgressBar) void {
        if (self.finished) return;
        self.finished = true;

        switch (output.getRenderMode()) {
            .silent => {},
            .pipe => {
                // Pipe: print a completion step line (no bar was drawn)
                var bytes_buf: [32]u8 = undefined;
                const final_bytes = self.bytes_total orelse self.bytes_done;
                const detail = fmtBytes(final_bytes, &bytes_buf);
                output.printStep(self.step, output.SYM_OK, detail);
            },
            .rich => {
                // Erase any stale trailing characters from a previously-longer
                // frame, then lock the bar in place.
                if (self.rendered) std.debug.print("\x1b[K\n", .{});
            },
            .plain => {
                if (self.rendered) std.debug.print("\n", .{});
            },
        }
    }
};

pub fn fmtBytes(bytes: u64, buf: []u8) []const u8 {
    if (bytes >= 1024 * 1024) {
        const mb = bytes / (1024 * 1024);
        const frac = (bytes % (1024 * 1024)) * 10 / (1024 * 1024);
        return std.fmt.bufPrint(buf, "{d}.{d} MB", .{ mb, frac }) catch "???";
    } else if (bytes >= 1024) {
        const kb = bytes / 1024;
        const frac = (bytes % 1024) * 10 / 1024;
        return std.fmt.bufPrint(buf, "{d}.{d} KB", .{ kb, frac }) catch "???";
    } else {
        return std.fmt.bufPrint(buf, "{d} B", .{bytes}) catch "???";
    }
}

// ─── Tests ────────────────────────────────────────────────────────────────────

test "fmtBytes: byte range" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("0 B", fmtBytes(0, &buf));
    try std.testing.expectEqualStrings("1 B", fmtBytes(1, &buf));
    try std.testing.expectEqualStrings("1023 B", fmtBytes(1023, &buf));
}

test "fmtBytes: kilobyte range" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("1.0 KB", fmtBytes(1024, &buf));
    try std.testing.expectEqualStrings("1.5 KB", fmtBytes(1536, &buf));
    try std.testing.expectEqualStrings("10.0 KB", fmtBytes(10240, &buf));
    // Boundary: one byte below 1 MB
    try std.testing.expectEqualStrings("1023.9 KB", fmtBytes(1024 * 1024 - 1, &buf));
}

test "fmtBytes: megabyte range" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("1.0 MB", fmtBytes(1024 * 1024, &buf));
    try std.testing.expectEqualStrings("15.2 MB", fmtBytes(15 * 1024 * 1024 + 256 * 1024, &buf));
    try std.testing.expectEqualStrings("100.0 MB", fmtBytes(100 * 1024 * 1024, &buf));
}

test "ProgressBar: update stores bytes" {
    output.setRenderModeForTesting(.silent);
    defer output.setRenderModeForTesting(.rich);
    var bar = ProgressBar{ .step = "Test" };
    bar.update(1024, 10240, "");
    try std.testing.expectEqual(@as(u64, 1024), bar.bytes_done);
    try std.testing.expectEqual(@as(?u64, 10240), bar.bytes_total);
    try std.testing.expect(!bar.finished);
}

test "ProgressBar: auto-finish triggers at 100%" {
    output.setRenderModeForTesting(.silent);
    defer output.setRenderModeForTesting(.rich);
    var bar = ProgressBar{ .step = "Test" };
    bar.update(50, 100, "");
    try std.testing.expect(!bar.finished);
    bar.update(100, 100, "");
    try std.testing.expect(bar.finished);
}

test "ProgressBar: auto-finish triggers when current exceeds total" {
    output.setRenderModeForTesting(.silent);
    defer output.setRenderModeForTesting(.rich);
    var bar = ProgressBar{ .step = "Test" };
    // Simulate final callback with total = bytes_done (unknown content-length path)
    bar.update(27_000_000, 27_000_000, "");
    try std.testing.expect(bar.finished);
    try std.testing.expectEqual(@as(u64, 27_000_000), bar.bytes_done);
}

test "ProgressBar: update is no-op after finish" {
    output.setRenderModeForTesting(.silent);
    defer output.setRenderModeForTesting(.rich);
    var bar = ProgressBar{ .step = "Test" };
    bar.update(100, 100, "");
    try std.testing.expect(bar.finished);
    // Further updates must not change bytes_done
    bar.update(200, 200, "");
    try std.testing.expectEqual(@as(u64, 100), bar.bytes_done);
}

test "ProgressBar: explicit finish is idempotent" {
    output.setRenderModeForTesting(.silent);
    defer output.setRenderModeForTesting(.rich);
    var bar = ProgressBar{ .step = "Test" };
    bar.finish();
    bar.finish(); // must not panic
    try std.testing.expect(bar.finished);
}

test "ProgressBar: finish without any update leaves rendered=false" {
    output.setRenderModeForTesting(.silent);
    defer output.setRenderModeForTesting(.rich);
    var bar = ProgressBar{ .step = "Test" };
    try std.testing.expect(!bar.rendered);
    bar.finish();
    try std.testing.expect(!bar.rendered);
}
