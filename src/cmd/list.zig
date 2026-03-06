const std = @import("std");
const tool_mod = @import("../tool.zig");
const state_mod = @import("../state.zig");
const registry = @import("../registry/mod.zig");
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

    var group_filter: ?tool_mod.Group = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--group") or std.mem.eql(u8, a, "-g")) {
            i += 1;
            if (i < args.len) group_filter = parseGroup(args[i]);
        }
    }

    printListHeader();

    var count: usize = 0;
    for (registry.all_tools) |t| {
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

        printListRow(t.id, t.description, state.isInstalled(t.id), groups_str.getWritten());
        count += 1;
    }

    const filter_name: ?[]const u8 = if (group_filter) |gf| @tagName(gf) else null;
    printListFooter(count, filter_name);
    _ = allocator;
}

// ─── List-specific print functions ────────────────────────────────────────────

fn printListHeader() void {
    std.debug.print("\n{s}{s}Available Tools{s}\n\n", .{ output.CYAN, output.BOLD, output.RESET });
    std.debug.print("{s}{s:<16} {s:<33} {s:<14} {s}{s}\n", .{
        output.BOLD, "Tool", "Description", "Status", "Groups", output.RESET,
    });
    std.debug.print("{s}", .{output.DIM});
    for (0..73) |_| std.debug.print(output.SYM_DASH, .{});
    std.debug.print("{s}\n", .{output.RESET});
}

fn printListRow(id: []const u8, desc: []const u8, installed: bool, groups: []const u8) void {
    const desc_trunc = desc[0..@min(desc.len, 33)];
    std.debug.print("{s:<16} {s:<33} ", .{ id, desc_trunc });
    // Status: hardcoded trailing spaces so visual column width = 14
    // "✓ installed"  = 11 visual chars → +3 spaces
    // "not installed" = 13 visual chars → +1 space
    if (installed) {
        std.debug.print(output.GREEN ++ output.SYM_OK ++ " installed" ++ output.RESET ++ "   ", .{});
    } else {
        std.debug.print(output.DIM ++ "not installed" ++ output.RESET ++ " ", .{});
    }
    std.debug.print("{s}\n", .{groups});
}

fn printListFooter(count: usize, group_filter: ?[]const u8) void {
    std.debug.print("\n{d} tools total", .{count});
    if (group_filter) |g| std.debug.print(" (filtered by group '{s}')", .{g});
    std.debug.print("\n\n", .{});
}

fn parseGroup(name: []const u8) ?tool_mod.Group {
    if (std.mem.eql(u8, name, "k8s")) return .k8s;
    if (std.mem.eql(u8, name, "cloud")) return .cloud;
    if (std.mem.eql(u8, name, "iac")) return .iac;
    if (std.mem.eql(u8, name, "containers")) return .containers;
    if (std.mem.eql(u8, name, "utils")) return .utils;
    if (std.mem.eql(u8, name, "terminal")) return .terminal;
    return null;
}
