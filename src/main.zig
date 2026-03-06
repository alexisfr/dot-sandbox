const std = @import("std");
const cli = @import("cli.zig");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    try cli.run(allocator, argv);
}

// Pull in all tests from submodules
test {
    _ = @import("platform.zig");
    _ = @import("tool.zig");
    _ = @import("registry/mod.zig");
    _ = @import("validate.zig");
    _ = @import("state.zig");
    _ = @import("shell.zig");
    _ = @import("cmd/install.zig");
    _ = @import("cmd/plugin.zig");
    _ = @import("cmd/upgrade.zig");
    _ = @import("cmd/uninstall.zig");
    _ = @import("cli.zig");
}
