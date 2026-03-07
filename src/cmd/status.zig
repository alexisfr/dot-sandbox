const std = @import("std");
const state_mod = @import("../state.zig");
const output = @import("../ui/output.zig");

const HELP =
    \\Usage: dot status
    \\
    \\Show all tools currently installed by dot, with version,
    \\install date, install method, and pin status.
    \\
    \\Options:
    \\  --help, -h    Show this help
    \\
;

// ─── Status-specific print functions ──────────────────────────────────────────

fn printStatusHeader() void {
    std.debug.print("\n{s}{s}Installed Tools{s}\n\n", .{ output.CYAN, output.BOLD, output.RESET });
    std.debug.print("{s}{s:<16} {s:<16} {s:<24} {s}{s}\n", .{
        output.BOLD, "Tool", "Version", "Installed At", "Method", output.RESET,
    });
    std.debug.print("{s}", .{output.DIM});
    for (0..72) |_| std.debug.print(output.SYM_DASH, .{});
    std.debug.print("{s}\n", .{output.RESET});
}

fn printStatusEmpty() void {
    std.debug.print("  No tools installed yet.\n\n", .{});
    std.debug.print("  Run 'dot install <tool>' to get started.\n\n", .{});
}

fn printStatusRow(id: []const u8, version: []const u8, installed_at: []const u8, method: []const u8) void {
    const at_trunc = installed_at[0..@min(installed_at.len, 23)];
    std.debug.print("{s:<16} {s}{s:<16}{s} {s:<24} {s}\n", .{
        id, output.GREEN, version, output.RESET, at_trunc, method,
    });
}

fn printStatusFooter(count: usize) void {
    std.debug.print("\n{d} tool(s) installed\n\n", .{count});
}

fn formatTimestamp(ts_str: []const u8, buf: []u8) []const u8 {
    const secs = std.fmt.parseInt(u64, ts_str, 10) catch return ts_str;
    const epoch_secs = std.time.epoch.EpochSeconds{ .secs = secs };
    const year_day = epoch_secs.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_secs = secs % (24 * 3600);
    const h = day_secs / 3600;
    const m = (day_secs % 3600) / 60;
    const s = day_secs % 60;
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        h, m, s,
    }) catch ts_str;
}

test "formatTimestamp" {
    var buf: [24]u8 = undefined;
    try std.testing.expectEqualStrings("1970-01-01 00:00:00", formatTimestamp("0", &buf));
    try std.testing.expectEqualStrings("1970-01-02 00:00:00", formatTimestamp("86400", &buf));
    try std.testing.expectEqualStrings("1970-01-01 01:01:01", formatTimestamp("3661", &buf));
    // invalid input → returned as-is
    try std.testing.expectEqualStrings("bad", formatTimestamp("bad", &buf));
}

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
) !void {
    _ = allocator;

    for (args) |a| {
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            output.printRaw(HELP);
            return;
        }
    }

    printStatusHeader();

    if (state.tools.count() == 0) {
        printStatusEmpty();
        return;
    }

    // Collect keys and sort alphabetically
    var keys: [256][]const u8 = undefined;
    var n: usize = 0;
    var kit = state.tools.iterator();
    while (kit.next()) |kv| {
        keys[n] = kv.key_ptr.*;
        n += 1;
    }
    const Cmp = struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    };
    std.mem.sort([]const u8, keys[0..n], {}, Cmp.lt);

    for (keys[0..n]) |k| {
        const t = state.tools.get(k).?;
        var date_buf: [24]u8 = undefined;
        const date = formatTimestamp(t.installed_at, &date_buf);
        printStatusRow(k, t.version, date, t.method);
    }

    printStatusFooter(state.tools.count());
}
