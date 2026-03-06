const std = @import("std");
const state_mod = @import("../state.zig");
const platform = @import("../platform.zig");
const shell_mod = @import("../shell.zig");
const output = @import("../ui/output.zig");
const validate = @import("../validate.zig");

const HELP =
    \\Usage: dot plugin <command>
    \\
    \\Commands:
    \\  list                List installed plugins
    \\  install <url|path>  Install a plugin from a URL or local path
    \\  uninstall <name>    Remove a plugin
    \\  update [name]       Update one or all plugins
    \\
    \\Options:
    \\  --help, -h    Show this help
    \\
    \\Plugin sources:
    \\  https://github.com/org/dot-myplugin.git   (git URL)
    \\  ./my-plugin.sh                            (local path)
    \\
    \\Plugins are executables named dot-<name> stored in
    \\~/.local/share/dot/plugins/ and callable as 'dot <name>'.
    \\
;

const INSTALL_HELP = "Usage: dot plugin install <url|path>\n";
const UNINSTALL_HELP = "Usage: dot plugin uninstall <name>\n";

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
) !void {
    if (args.len == 0) {
        output.printRaw(HELP);
        return;
    }

    const sub = args[0];

    if (std.mem.eql(u8, sub, "--help") or std.mem.eql(u8, sub, "-h")) {
        output.printRaw(HELP);
        return;
    }
    const rest = if (args.len > 1) args[1..] else &[_][]const u8{};

    if (std.mem.eql(u8, sub, "list")) {
        try listPlugins(state);
    } else if (std.mem.eql(u8, sub, "install")) {
        if (rest.len == 0) {
            output.printRaw(INSTALL_HELP);
            return;
        }
        try installPlugin(allocator, rest[0], state);
    } else if (std.mem.eql(u8, sub, "uninstall") or std.mem.eql(u8, sub, "remove")) {
        if (rest.len == 0) {
            output.printRaw(UNINSTALL_HELP);
            return;
        }
        try uninstallPlugin(allocator, rest[0], state);
    } else if (std.mem.eql(u8, sub, "update")) {
        const name: ?[]const u8 = if (rest.len > 0) rest[0] else null;
        try updatePlugins(allocator, name, state);
    } else {
        output.printFmt("Unknown plugin subcommand: {s}\n", .{sub});
        output.printRaw(HELP);
    }
}

fn listPlugins(state: *state_mod.State) !void {
    printPluginListHeader();

    if (state.plugins.count() == 0) {
        output.printRaw("  No plugins installed.\n\n  Run 'dot plugin install <url>' to add a plugin.\n\n");
        return;
    }

    var it = state.plugins.iterator();
    while (it.next()) |kv| {
        const p = kv.value_ptr.*;
        printPluginRow(kv.key_ptr.*, p.version, p.source_url);
    }
    output.printRaw("\n");
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

    printPluginInstalling(plugin_name, source);

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
        printPluginSourceError(source);
        return;
    }

    const sh = platform.Shell.detect();
    if (sh != .unknown) {
        shell_mod.ensurePluginPath(sh, allocator) catch {};
    }

    try state.addPlugin(plugin_name, source, "latest");
    printPluginInstalled(plugin_name);
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
        output.printRaw("  git clone failed\n");
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

    printPluginRepoWarning();
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
        output.printFmt("Plugin '{s}' is not installed\n", .{name});
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
    output.printFmt("Removed plugin 'dot-{s}'\n", .{name});
}

fn updatePlugins(
    allocator: std.mem.Allocator,
    name: ?[]const u8,
    state: *state_mod.State,
) !void {
    if (name) |n| {
        const entry = state.plugins.get(n) orelse {
            output.printFmt("Plugin '{s}' is not installed\n", .{n});
            return;
        };
        try installPlugin(allocator, entry.source_url, state);
    } else {
        var it = state.plugins.iterator();
        while (it.next()) |kv| {
            installPlugin(allocator, kv.value_ptr.*.source_url, state) catch |e| {
                output.printFmt("Failed to update {s}: {s}\n", .{ kv.key_ptr.*, @errorName(e) });
            };
        }
    }
}

// ─── Plugin-specific print functions ──────────────────────────────────────────

fn printPluginListHeader() void {
    std.debug.print("\n{s}{s}Installed Plugins{s}\n\n", .{ output.CYAN, output.BOLD, output.RESET });
}

fn printPluginRow(name: []const u8, version: []const u8, source: []const u8) void {
    std.debug.print("  {s}dot-{s}{s}  {s}  {s}\n", .{ output.GREEN, name, output.RESET, version, source });
}

fn printPluginInstalling(name: []const u8, source: []const u8) void {
    std.debug.print("{s} Installing plugin '{s}' from {s}...\n", .{ output.SYM_PLUG, name, source });
}

fn printPluginInstalled(name: []const u8) void {
    std.debug.print("{s}{s}{s} Plugin 'dot-{s}' installed\n\n", .{ output.GREEN, output.SYM_CHECK, output.RESET, name });
}

fn printPluginSourceError(source: []const u8) void {
    std.debug.print("{s}Error:{s} unrecognised source format '{s}'\n", .{ output.RED, output.RESET, source });
    std.debug.print("  Expected: https://... URL or local path ./plugin\n", .{});
}

fn printPluginRepoWarning() void {
    std.debug.print("  {s}Warning:{s} no executable found in repo, copying repo as-is\n", .{ output.YELLOW, output.RESET });
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
