const std = @import("std");
const state_mod = @import("../state.zig");
const platform = @import("../platform.zig");
const shell_mod = @import("../shell.zig");
const output = @import("../ui/output.zig");
const validate = @import("../validate.zig");

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
) !void {
    if (args.len == 0) {
        output.printPluginUsage();
        return;
    }

    const sub = args[0];
    const rest = if (args.len > 1) args[1..] else &[_][]const u8{};

    if (std.mem.eql(u8, sub, "list")) {
        try listPlugins(state);
    } else if (std.mem.eql(u8, sub, "install")) {
        if (rest.len == 0) {
            output.printPluginInstallUsage();
            return;
        }
        try installPlugin(allocator, rest[0], state);
    } else if (std.mem.eql(u8, sub, "uninstall") or std.mem.eql(u8, sub, "remove")) {
        if (rest.len == 0) {
            output.printPluginUninstallUsage();
            return;
        }
        try uninstallPlugin(allocator, rest[0], state);
    } else if (std.mem.eql(u8, sub, "update")) {
        const name: ?[]const u8 = if (rest.len > 0) rest[0] else null;
        try updatePlugins(allocator, name, state);
    } else {
        output.printUnknownPluginSubcmd(sub);
        output.printPluginUsage();
    }
}

fn listPlugins(state: *state_mod.State) !void {
    output.printPluginListHeader();

    if (state.plugins.count() == 0) {
        output.printPluginEmpty();
        return;
    }

    var it = state.plugins.iterator();
    while (it.next()) |kv| {
        const p = kv.value_ptr.*;
        output.printPluginRow(kv.key_ptr.*, p.version, p.source_url);
    }
    output.printPluginListEnd();
}

fn installPlugin(
    allocator: std.mem.Allocator,
    source: []const u8,
    state: *state_mod.State,
) !void {
    if (!validate.isValidPluginSource(source)) {
        output.printError("invalid plugin source: must be an https/http URL or a local path");
        return error.InvalidPluginSource;
    }

    const home = std.posix.getenv("HOME") orelse return error.NoHome;
    const plugin_dir = try std.fs.path.join(allocator, &.{
        home, ".local", "share", "dot", "plugins",
    });
    defer allocator.free(plugin_dir);
    try std.fs.cwd().makePath(plugin_dir);

    const plugin_name = pluginNameFromSource(source);

    output.printPluginInstalling(plugin_name, source);

    if (std.mem.startsWith(u8, source, "https://") or std.mem.startsWith(u8, source, "http://")) {
        try installFromGit(allocator, source, plugin_name, plugin_dir);
    } else if (std.mem.startsWith(u8, source, "./") or std.mem.startsWith(u8, source, "/")) {
        const dest_name = try std.fmt.allocPrint(allocator, "dot-{s}", .{plugin_name});
        defer allocator.free(dest_name);
        const dest = try std.fs.path.join(allocator, &.{ plugin_dir, dest_name });
        defer allocator.free(dest);
        try std.fs.cwd().copyFile(source, std.fs.cwd(), dest, .{});
        _ = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "chmod", "+x", dest },
        });
    } else {
        output.printPluginSourceError(source);
        return;
    }

    const sh = platform.Shell.detect();
    if (sh != .unknown) {
        shell_mod.ensurePluginPath(sh, allocator) catch {};
    }

    try state.addPlugin(plugin_name, source, "latest");
    output.printPluginInstalled(plugin_name);
}

fn installFromGit(
    allocator: std.mem.Allocator,
    url: []const u8,
    name: []const u8,
    plugin_dir: []const u8,
) !void {
    const tmp_dir = try std.fmt.allocPrint(allocator, "/tmp/dot-plugin-{s}", .{name});
    defer allocator.free(tmp_dir);
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};

    const clone_res = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "clone", "--depth=1", url, tmp_dir },
    });
    defer allocator.free(clone_res.stdout);
    defer allocator.free(clone_res.stderr);

    if (clone_res.term.Exited != 0) {
        output.printPluginGitError();
        return error.GitCloneFailed;
    }

    const candidates = [_][]const u8{
        try std.fmt.allocPrint(allocator, "dot-{s}", .{name}),
        name,
        "main.sh",
        "plugin.sh",
    };
    defer for (candidates) |c| allocator.free(c);

    const dest_name = try std.fmt.allocPrint(allocator, "dot-{s}", .{name});
    defer allocator.free(dest_name);
    const dest = try std.fs.path.join(allocator, &.{ plugin_dir, dest_name });
    defer allocator.free(dest);

    for (candidates) |c| {
        const src = try std.fs.path.join(allocator, &.{ tmp_dir, c });
        defer allocator.free(src);
        std.fs.cwd().access(src, .{}) catch continue;
        try std.fs.cwd().copyFile(src, std.fs.cwd(), dest, .{});
        _ = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "chmod", "+x", dest },
        });
        return;
    }

    output.printPluginRepoWarning();
}

fn uninstallPlugin(
    allocator: std.mem.Allocator,
    name: []const u8,
    state: *state_mod.State,
) !void {
    if (!validate.isValidToolId(name)) {
        output.printError("invalid plugin name");
        return error.InvalidPluginName;
    }

    if (!state.plugins.contains(name)) {
        output.printPluginNotFound(name);
        return;
    }

    const home = std.posix.getenv("HOME") orelse return error.NoHome;
    const plugin_path = try std.fmt.allocPrint(
        allocator,
        "{s}/.local/share/dot/plugins/dot-{s}",
        .{ home, name },
    );
    defer allocator.free(plugin_path);

    std.fs.cwd().deleteFile(plugin_path) catch {};
    try state.removePlugin(name);
    output.printPluginRemoved(name);
}

fn updatePlugins(
    allocator: std.mem.Allocator,
    name: ?[]const u8,
    state: *state_mod.State,
) !void {
    if (name) |n| {
        const entry = state.plugins.get(n) orelse {
            output.printPluginNotFound(n);
            return;
        };
        try installPlugin(allocator, entry.source_url, state);
    } else {
        var it = state.plugins.iterator();
        while (it.next()) |kv| {
            installPlugin(allocator, kv.value_ptr.*.source_url, state) catch |e| {
                output.printPluginUpdateFailed(kv.key_ptr.*, e);
            };
        }
    }
}

fn pluginNameFromSource(source: []const u8) []const u8 {
    const base = std.fs.path.basename(source);
    const stripped = if (std.mem.endsWith(u8, base, ".git")) base[0 .. base.len - 4] else base;
    return if (std.mem.startsWith(u8, stripped, "dot-")) stripped[4..] else stripped;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

test "pluginNameFromSource: git URL with .git suffix" {
    try std.testing.expectEqualStrings("myplugin", pluginNameFromSource("https://github.com/org/myplugin.git"));
}

test "pluginNameFromSource: git URL without .git suffix" {
    try std.testing.expectEqualStrings("myplugin", pluginNameFromSource("https://github.com/org/myplugin"));
}

test "pluginNameFromSource: dot- prefix stripped" {
    try std.testing.expectEqualStrings("myplugin", pluginNameFromSource("https://github.com/org/dot-myplugin.git"));
}

test "pluginNameFromSource: local path" {
    try std.testing.expectEqualStrings("my-plugin.sh", pluginNameFromSource("./my-plugin.sh"));
}

test "pluginNameFromSource: absolute path" {
    try std.testing.expectEqualStrings("my-plugin", pluginNameFromSource("/usr/local/bin/my-plugin"));
}
