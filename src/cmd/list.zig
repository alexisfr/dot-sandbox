const std = @import("std");
const builtin = @import("builtin");
const tool_mod = @import("../tool.zig");
const state_mod = @import("../state.zig");
const output = @import("../ui/output.zig");

const HELP =
    \\Usage: dot list [--group <group>]
    \\
    \\List all tools in the registry with their install status.
    \\
    \\Options:
    \\  --group, -g <g>   Show only tools in the given group
    \\  --help, -h        Show this help
    \\
    \\Groups:  k8s, cloud, iac, containers, utils, terminal, all
    \\
    \\Examples:
    \\  dot list
    \\  dot list --group k8s
    \\
;

// Fixed column widths (visual chars)
const COL_ID: usize = 16;
const COL_STATUS: usize = 14;  // "✓ 1.35.2      " or "not installed "
const COL_GROUPS: usize = 16;
// Overhead: id(16) + sp(1) + status(14) + sp(1) + groups(16) + sp(1) = 49
// Description is rightmost — no reserve needed, gets all remaining space
const OVERHEAD: usize = 49;
const DESC_MIN: usize = 10;

fn getTermWidth() usize {
    if (comptime builtin.os.tag == .linux) {
        const Winsize = extern struct { ws_row: u16, ws_col: u16, ws_xpixel: u16, ws_ypixel: u16 };
        var ws = std.mem.zeroes(Winsize);
        _ = std.os.linux.ioctl(1, 0x5413, @intFromPtr(&ws)); // TIOCGWINSZ
        if (ws.ws_col > 0) return @as(usize, ws.ws_col);
    }
    if (std.posix.getenv("COLUMNS")) |cols| return std.fmt.parseInt(usize, cols, 10) catch 80;
    return 80;
}

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
    tools: []const tool_mod.Tool,
) !void {
    for (args) |a| {
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            output.printRaw(HELP);
            return;
        }
    }

    var group_filter: ?tool_mod.Group = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--group") or std.mem.eql(u8, a, "-g")) {
            i += 1;
            if (i < args.len) group_filter = parseGroup(args[i]);
        }
    }

    const term_width = getTermWidth();
    const desc_width = if (term_width > OVERHEAD) term_width - OVERHEAD else DESC_MIN;

    printListHeader(term_width);

    var count: usize = 0;
    for (tools) |t| {
        if (group_filter) |gf| {
            var in_group = false;
            for (t.groups) |g| {
                if (g == gf) { in_group = true; break; }
            }
            if (!in_group) continue;
        }

        var groups_buf: [64]u8 = undefined;
        var groups_str = std.io.fixedBufferStream(&groups_buf);
        const gw = groups_str.writer();
        for (t.groups, 0..) |g, idx| {
            if (idx > 0) gw.writeByte(',') catch {};
            gw.writeAll(@tagName(g)) catch {};
        }

        const maybe_entry = state.tools.get(t.id);
        const version: ?[]const u8 = if (maybe_entry) |e| e.version else null;
        printListRow(t.id, t.aliases, t.description, version, groups_str.getWritten(), desc_width);
        count += 1;
    }

    const filter_name: ?[]const u8 = if (group_filter) |gf| @tagName(gf) else null;
    printListFooter(count, filter_name);
    _ = allocator;
}

// ─── List-specific print functions ────────────────────────────────────────────

fn printListHeader(term_width: usize) void {
    std.debug.print("\n{s}{s}Available Tools{s}\n\n", .{ output.CYAN, output.BOLD, output.RESET });
    std.debug.print("{s}{s:<16} {s:<14} {s:<16} Description{s}\n", .{
        output.BOLD, "Tool", "Status", "Groups", output.RESET,
    });
    std.debug.print("{s}", .{output.DIM});
    for (0..@min(term_width, 200)) |_| std.debug.print(output.SYM_DASH, .{});
    std.debug.print("{s}\n", .{output.RESET});
}

/// Truncate desc to at most max_visual visual chars, breaking at a word boundary
/// and appending UTF-8 '…' if truncated. Returns the byte slice and its visual width.
fn truncDesc(desc: []const u8, max_visual: usize, buf: []u8) struct { str: []const u8, visual: usize } {
    if (desc.len <= max_visual) return .{ .str = desc, .visual = desc.len };
    // Walk back from max_visual-1 to find a space (leave room for …)
    var end: usize = max_visual - 1;
    while (end > 0 and desc[end] != ' ') : (end -= 1) {}
    const cut = if (end == 0) max_visual - 1 else end;
    @memcpy(buf[0..cut], desc[0..cut]);
    buf[cut] = 0xe2; buf[cut + 1] = 0x80; buf[cut + 2] = 0xa6; // UTF-8 '…'
    return .{ .str = buf[0 .. cut + 3], .visual = cut + 1 };
}

fn printListRow(id: []const u8, aliases: []const []const u8, desc: []const u8, version: ?[]const u8, groups: []const u8, desc_width: usize) void {
    // id column: "kubectl" or "kubectl (k)" dimmed, padded to COL_ID visual chars
    const id_trunc = id[0..@min(id.len, COL_ID)];
    if (aliases.len > 0) {
        // Build alias string e.g. "(k)" or "(k,tf)"
        var alias_buf: [32]u8 = undefined;
        var alias_fbs = std.io.fixedBufferStream(&alias_buf);
        const aw = alias_fbs.writer();
        aw.writeByte('(') catch {};
        for (aliases, 0..) |a, i| {
            if (i > 0) aw.writeByte(',') catch {};
            aw.writeAll(a) catch {};
        }
        aw.writeByte(')') catch {};
        const alias_str = alias_fbs.getWritten();

        // Visual width: id + 1 space + alias_str
        const visual = id_trunc.len + 1 + alias_str.len;
        const pad = if (COL_ID + 1 > visual) COL_ID + 1 - visual else 0;
        std.debug.print("{s} {s}{s}{s}", .{ id_trunc, output.DIM, alias_str, output.RESET });
        for (0..pad) |_| std.debug.print(" ", .{});
    } else {
        std.debug.print("{s:<16} ", .{id_trunc});
    }

    // status column: 14 visual chars + 1 trailing space = 15 total
    if (version) |v| {
        const v_trunc = v[0..@min(v.len, 12)];
        std.debug.print(output.GREEN ++ output.SYM_OK ++ " {s:<12}" ++ output.RESET ++ " ", .{v_trunc});
    } else {
        std.debug.print(output.DIM ++ "not installed" ++ output.RESET ++ "  ", .{});
    }

    // groups column — ASCII, byte-pad fine; truncate if somehow over COL_GROUPS
    const g_trunc = groups[0..@min(groups.len, COL_GROUPS)];
    std.debug.print("{s:<16} ", .{g_trunc});

    // description — rightmost, no padding needed; truncate to fit terminal
    var desc_buf: [512]u8 = undefined;
    const res = truncDesc(desc, desc_width, &desc_buf);
    std.debug.print("{s}\n", .{res.str});
}

fn printListFooter(count: usize, group_filter: ?[]const u8) void {
    std.debug.print("\n{d} tools total", .{count});
    if (group_filter) |g| std.debug.print(" (filtered by group '{s}')", .{g});
    std.debug.print("\n\n", .{});
}

test "truncDesc" {
    var buf: [512]u8 = undefined;

    // Short string — returned as-is
    const r1 = truncDesc("hello", 20, &buf);
    try std.testing.expectEqualStrings("hello", r1.str);
    try std.testing.expectEqual(@as(usize, 5), r1.visual);

    // Exactly max_visual — no truncation
    const r2 = truncDesc("hello world", 11, &buf);
    try std.testing.expectEqualStrings("hello world", r2.str);
    try std.testing.expectEqual(@as(usize, 11), r2.visual);

    // Truncate at word boundary: "hello world foo", max=12
    // end=11 → desc[11]=' ' → cut=11 → "hello world…", visual=12
    const r3 = truncDesc("hello world foo", 12, &buf);
    try std.testing.expectEqualStrings("hello world\xe2\x80\xa6", r3.str);
    try std.testing.expectEqual(@as(usize, 12), r3.visual);

    // No space found — hard cut at max_visual-1
    // "helloworldfoo", max=5 → cut=4 → "hell…", visual=5
    const r4 = truncDesc("helloworldfoo", 5, &buf);
    try std.testing.expectEqualStrings("hell\xe2\x80\xa6", r4.str);
    try std.testing.expectEqual(@as(usize, 5), r4.visual);
}

test "parseGroup" {
    try std.testing.expectEqual(@as(?tool_mod.Group, null), parseGroup("all"));
    try std.testing.expectEqual(@as(?tool_mod.Group, null), parseGroup("unknown"));
    try std.testing.expectEqual(@as(?tool_mod.Group, .k8s), parseGroup("k8s"));
    try std.testing.expectEqual(@as(?tool_mod.Group, .cloud), parseGroup("cloud"));
    try std.testing.expectEqual(@as(?tool_mod.Group, .containers), parseGroup("containers"));
}

fn parseGroup(name: []const u8) ?tool_mod.Group {
    if (std.mem.eql(u8, name, "all")) return null; // null = no filter = show all
    if (std.mem.eql(u8, name, "k8s")) return .k8s;
    if (std.mem.eql(u8, name, "cloud")) return .cloud;
    if (std.mem.eql(u8, name, "iac")) return .iac;
    if (std.mem.eql(u8, name, "containers")) return .containers;
    if (std.mem.eql(u8, name, "utils")) return .utils;
    if (std.mem.eql(u8, name, "terminal")) return .terminal;
    return null;
}
