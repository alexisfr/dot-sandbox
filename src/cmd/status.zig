const std = @import("std");
const state_mod = @import("../state.zig");
const registry = @import("../registry/mod.zig");

const CYAN = "\x1b[0;36m";
const GREEN = "\x1b[1;32m";
const YELLOW = "\x1b[1;33m";
const DIM = "\x1b[2m";
const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
) !void {
    _ = args;
    _ = allocator;

    std.debug.print("\n{s}{s}Installed Tools{s}\n\n", .{ CYAN, BOLD, RESET });

    if (state.tools.count() == 0) {
        std.debug.print("  No tools installed yet.\n\n", .{});
        std.debug.print("  Run 'dot install <tool>' to get started.\n\n", .{});
        return;
    }

    std.debug.print("{s}{s:<16} {s:<16} {s:<24} {s}{s}\n", .{
        BOLD, "Tool", "Version", "Installed At", "Method", RESET,
    });
    std.debug.print("{s}", .{DIM});
    var i: usize = 0;
    while (i < 72) : (i += 1) std.debug.print("─", .{});
    std.debug.print("{s}\n", .{RESET});

    var it = state.tools.iterator();
    while (it.next()) |kv| {
        const t = kv.value_ptr.*;
        const installed_at_trunc = if (t.installed_at.len > 23) t.installed_at[0..23] else t.installed_at;

        std.debug.print("{s:<16} {s}{s:<16}{s} {s:<24} {s}\n", .{
            kv.key_ptr.*,
            GREEN,
            t.version,
            RESET,
            installed_at_trunc,
            t.method,
        });
    }
    std.debug.print("\n{d} tool(s) installed\n\n", .{state.tools.count()});
}
