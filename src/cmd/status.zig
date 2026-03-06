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

    var it = state.tools.iterator();
    while (it.next()) |kv| {
        const t = kv.value_ptr.*;
        printStatusRow(kv.key_ptr.*, t.version, t.installed_at, t.method);
    }

    printStatusFooter(state.tools.count());
}
