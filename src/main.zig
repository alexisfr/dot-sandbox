const std = @import("std");
const cli = @import("cli.zig");

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    cli.run(allocator, argv) catch |e| switch (e) {
        // CommandFailed means the command already printed its own error message.
        // Exit with code 1 without printing anything — avoids the double "error: Foo" line.
        error.CommandFailed => std.process.exit(1),
        else => return e,
    };
}

// Pull in all tests from submodules
test {
    _ = @import("platform.zig");
    _ = @import("tool.zig");
    _ = @import("archive.zig");
    _ = @import("repository/loader.zig");
    _ = @import("validate.zig");
    _ = @import("util.zig");
    _ = @import("state.zig");
    _ = @import("shell.zig");
    _ = @import("ui/output.zig");
    _ = @import("ui/progress.zig");
    _ = @import("cmd/install.zig");
    _ = @import("cmd/upgrade.zig");
    _ = @import("cmd/uninstall.zig");
    _ = @import("cmd/list.zig");
    _ = @import("cmd/repository.zig");
    _ = @import("cmd/doctor.zig");
    _ = @import("cmd/groups.zig");
    _ = @import("cmd/info.zig");
    _ = @import("cmd/outdated.zig");
    _ = @import("cmd/search.zig");
    _ = @import("cmd/pin.zig");
    _ = @import("cmd/unpin.zig");
    _ = @import("cli.zig");
}
