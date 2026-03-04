const std = @import("std");
const state_mod = @import("state.zig");
const install_cmd = @import("cmd/install.zig");
const list_cmd = @import("cmd/list.zig");
const status_cmd = @import("cmd/status.zig");
const doctor_cmd = @import("cmd/doctor.zig");
const upgrade_cmd = @import("cmd/upgrade.zig");
const plugin_cmd = @import("cmd/plugin.zig");
const output = @import("ui/output.zig");

pub fn run(allocator: std.mem.Allocator, argv: [][:0]u8) !void {
    if (argv.len < 2) {
        output.printHelp();
        return;
    }

    const command: []const u8 = argv[1];

    if (std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "-v")) {
        output.printVersion();
        return;
    }

    if (std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h") or std.mem.eql(u8, command, "help")) {
        output.printHelp();
        return;
    }

    // Convert argv[2..] to [][]const u8
    var rest: std.ArrayList([]const u8) = .empty;
    defer rest.deinit(allocator);
    for (argv[2..]) |a| {
        try rest.append(allocator, @as([]const u8, a));
    }
    const args = rest.items;

    if (std.mem.eql(u8, command, "list")) {
        var state = try state_mod.State.init(allocator);
        defer state.deinit();
        return list_cmd.run(allocator, args, &state);
    }

    if (std.mem.eql(u8, command, "doctor")) {
        var state = try state_mod.State.init(allocator);
        defer state.deinit();
        return doctor_cmd.run(allocator, args, &state);
    }

    if (std.mem.eql(u8, command, "install")) {
        var state = try state_mod.State.init(allocator);
        defer state.deinit();
        return install_cmd.run(allocator, args, &state);
    }

    if (std.mem.eql(u8, command, "status")) {
        var state = try state_mod.State.init(allocator);
        defer state.deinit();
        return status_cmd.run(allocator, args, &state);
    }

    if (std.mem.eql(u8, command, "upgrade")) {
        var state = try state_mod.State.init(allocator);
        defer state.deinit();
        return upgrade_cmd.run(allocator, args, &state);
    }

    if (std.mem.eql(u8, command, "plugin")) {
        var state = try state_mod.State.init(allocator);
        defer state.deinit();
        return plugin_cmd.run(allocator, args, &state);
    }

    // Plugin dispatch: dot <cmd> → try dot-<cmd> in PATH
    if (tryPluginDispatch(allocator, command, args)) {
        return;
    }

    output.printUnknownCommand(command);
}

/// Try to dispatch to an external dot-<cmd> plugin executable.
/// Returns true if the plugin was found and execed.
fn tryPluginDispatch(allocator: std.mem.Allocator, cmd: []const u8, args: []const []const u8) bool {
    const plugin_exe = std.fmt.allocPrint(allocator, "dot-{s}", .{cmd}) catch return false;
    defer allocator.free(plugin_exe);

    const check = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "sh", "-c", std.fmt.allocPrint(allocator, "command -v {s}", .{plugin_exe}) catch return false },
    }) catch return false;
    defer allocator.free(check.stdout);
    defer allocator.free(check.stderr);

    if (check.term.Exited != 0) return false;

    var plugin_argv: std.ArrayList([]const u8) = .empty;
    defer plugin_argv.deinit(allocator);

    plugin_argv.append(allocator, plugin_exe) catch return false;
    for (args) |a| plugin_argv.append(allocator, a) catch return false;

    var child = std.process.Child.init(plugin_argv.items, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    child.spawn() catch return false;
    _ = child.wait() catch {};
    return true;
}
