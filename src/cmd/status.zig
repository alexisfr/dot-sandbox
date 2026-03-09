const std = @import("std");
const state_mod = @import("../state.zig");
const output = @import("../ui/output.zig");
const http = @import("../http.zig");
const dot_version = @import("../version.zig");

const HELP =
    \\Usage: dot status
    \\
    \\Show all tools currently installed by dot, with version,
    \\install date, and install method.
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
    for (0..72) |_| std.debug.print("{s}", .{output.SYM_DASH});
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

fn checkDotUpdate(allocator: std.mem.Allocator) void {
    const url = "https://api.github.com/repos/" ++ dot_version.GITHUB_REPO ++ "/releases/latest";
    const body = http.get(allocator, url) catch return;
    defer allocator.free(body);

    const Release = struct { tag_name: []const u8 = "" };
    const parsed = std.json.parseFromSlice(Release, allocator, body, .{ .ignore_unknown_fields = true }) catch return;
    defer parsed.deinit();

    const tag = parsed.value.tag_name;
    if (tag.len == 0) return;
    const latest = if (tag[0] == 'v') tag[1..] else tag;

    if (!std.mem.eql(u8, latest, dot_version.CURRENT)) {
        std.debug.print("\n{s}ℹ{s}  dot v{s} available → https://github.com/" ++ dot_version.GITHUB_REPO ++ "/releases\n\n", .{ output.CYAN, output.RESET, latest });
    }
}

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
) !void {

    for (args) |a| {
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            output.printRaw(HELP);
            return;
        }
    }

    printStatusHeader();

    if (state.tools.count() == 0) {
        printStatusEmpty();
        checkDotUpdate(allocator);
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
    checkDotUpdate(allocator);
}
