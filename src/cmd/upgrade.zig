const std = @import("std");
const state_mod = @import("../state.zig");
const registry = @import("../registry/mod.zig");
const install_cmd = @import("install.zig");

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
) !void {
    if (args.len == 0) {
        // Upgrade all installed tools
        std.debug.print("Upgrading all installed tools...\n\n", .{});
        var it = state.tools.iterator();
        var to_upgrade: std.ArrayList([]const u8) = .empty;
        defer to_upgrade.deinit(allocator);

        while (it.next()) |kv| {
            try to_upgrade.append(allocator, kv.key_ptr.*);
        }

        for (to_upgrade.items) |id| {
            const upgrade_args = [_][]const u8{ id, "--force" };
            install_cmd.run(allocator, &upgrade_args, state) catch |e| {
                std.debug.print("Failed to upgrade {s}: {}\n", .{ id, e });
            };
        }
    } else {
        // Upgrade specific tool
        const id = args[0];
        if (registry.findById(id) == null) {
            std.debug.print("Error: unknown tool '{s}'\n", .{id});
            return;
        }
        const upgrade_args = [_][]const u8{ id, "--force" };
        try install_cmd.run(allocator, &upgrade_args, state);
    }
}
