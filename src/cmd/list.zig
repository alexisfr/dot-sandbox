const std = @import("std");
const tool_mod = @import("../tool.zig");
const state_mod = @import("../state.zig");
const registry = @import("../registry/mod.zig");

const CYAN = "\x1b[0;36m";
const GREEN = "\x1b[1;32m";
const DIM = "\x1b[2m";
const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
) !void {
    var group_filter: ?tool_mod.Group = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--group") or std.mem.eql(u8, a, "-g")) {
            i += 1;
            if (i < args.len) {
                group_filter = parseGroup(args[i]);
            }
        }
    }

    // Column visual widths: Tool=16, Desc=33, Status=14 ("not installed"+1 or "✓ installed"+3)
    std.debug.print("\n{s}{s}Available Tools{s}\n\n", .{ CYAN, BOLD, RESET });
    std.debug.print("{s}{s:<16} {s:<33} {s:<14} {s}{s}\n", .{
        BOLD, "Tool", "Description", "Status", "Groups", RESET,
    });
    std.debug.print("{s}", .{DIM});
    for (0..73) |_| std.debug.print("─", .{});
    std.debug.print("{s}\n", .{RESET});

    for (registry.all_tools) |t| {
        // Apply group filter
        if (group_filter) |gf| {
            var in_group = false;
            for (t.groups) |g| {
                if (g == gf) { in_group = true; break; }
            }
            if (!in_group) continue;
        }

        // Groups as string
        var groups_buf: [64]u8 = undefined;
        var groups_str = std.io.fixedBufferStream(&groups_buf);
        const gw = groups_str.writer();
        for (t.groups, 0..) |g, idx| {
            if (idx > 0) gw.writeByte(',') catch {};
            gw.writeAll(@tagName(g)) catch {};
        }
        const groups = groups_str.getWritten();

        const desc = t.description[0..@min(t.description.len, 33)];

        // Print id and description with format padding (no ANSI = byte == visual)
        std.debug.print("{s:<16} {s:<33} ", .{ t.id, desc });

        // Status: print color+text+reset then hardcoded spaces to reach visual col width 14.
        // "✓ installed"  = 11 visual chars → pad 3 spaces
        // "not installed" = 13 visual chars → pad 1 space
        if (state.isInstalled(t.id)) {
            std.debug.print(GREEN ++ "✓ installed" ++ RESET ++ "   ", .{});
        } else {
            std.debug.print(DIM ++ "not installed" ++ RESET ++ " ", .{});
        }

        std.debug.print("{s}\n", .{groups});
    }

    std.debug.print("\n{d} tools total", .{registry.all_tools.len});
    if (group_filter) |gf| {
        std.debug.print(" (filtered by group '{s}')", .{@tagName(gf)});
    }
    std.debug.print("\n\n", .{});
    _ = allocator;
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
