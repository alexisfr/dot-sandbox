const std = @import("std");
const state_mod = @import("../state.zig");
const platform = @import("../platform.zig");
const shell_mod = @import("../shell.zig");

const GREEN = "\x1b[1;32m";
const CYAN = "\x1b[0;36m";
const RED = "\x1b[1;31m";
const BOLD = "\x1b[1m";
const DIM = "\x1b[2m";
const RESET = "\x1b[0m";

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
) !void {
    if (args.len == 0) {
        printUsage();
        return;
    }

    const sub = args[0];
    const rest = if (args.len > 1) args[1..] else &.{};

    if (std.mem.eql(u8, sub, "list")) {
        try listPlugins(state);
    } else if (std.mem.eql(u8, sub, "install")) {
        if (rest.len == 0) {
            std.debug.print("Usage: dot plugin install <url|name>\n", .{});
            return;
        }
        try installPlugin(allocator, rest[0], state);
    } else if (std.mem.eql(u8, sub, "uninstall") or std.mem.eql(u8, sub, "remove")) {
        if (rest.len == 0) {
            std.debug.print("Usage: dot plugin uninstall <name>\n", .{});
            return;
        }
        try uninstallPlugin(allocator, rest[0], state);
    } else if (std.mem.eql(u8, sub, "update")) {
        const name: ?[]const u8 = if (rest.len > 0) rest[0] else null;
        try updatePlugins(allocator, name, state);
    } else {
        std.debug.print("Unknown plugin subcommand: {s}\n", .{sub});
        printUsage();
    }
}

fn listPlugins(state: *state_mod.State) !void {
    std.debug.print("\n{s}{s}Installed Plugins{s}\n\n", .{ CYAN, BOLD, RESET });

    if (state.plugins.count() == 0) {
        std.debug.print("  No plugins installed.\n\n", .{});
        std.debug.print("  Run 'dot plugin install <url>' to add a plugin.\n\n", .{});
        return;
    }

    var it = state.plugins.iterator();
    while (it.next()) |kv| {
        const p = kv.value_ptr.*;
        std.debug.print("  {s}dot-{s}{s}  {s}  {s}\n", .{
            GREEN, kv.key_ptr.*, RESET, p.version, p.source_url,
        });
    }
    std.debug.print("\n", .{});
}

fn installPlugin(
    allocator: std.mem.Allocator,
    source: []const u8,
    state: *state_mod.State,
) !void {
    const home = std.posix.getenv("HOME") orelse return error.NoHome;
    const plugin_dir = try std.fs.path.join(allocator, &.{
        home, ".local", "share", "dot", "plugins",
    });
    defer allocator.free(plugin_dir);
    try std.fs.cwd().makePath(plugin_dir);

    // Determine plugin name from URL or name
    const plugin_name = pluginNameFromSource(source);

    std.debug.print("🔌 Installing plugin '{s}' from {s}...\n", .{ plugin_name, source });

    // Check if it's a git URL
    if (std.mem.startsWith(u8, source, "https://") or std.mem.startsWith(u8, source, "http://")) {
        try installFromGit(allocator, source, plugin_name, plugin_dir);
    } else if (std.mem.startsWith(u8, source, "./") or std.mem.startsWith(u8, source, "/")) {
        // Local file
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
        std.debug.print("Error: unrecognised source format '{s}'\n", .{source});
        std.debug.print("  Expected: https://... URL or local path ./plugin\n", .{});
        return;
    }

    // Ensure plugin dir in PATH
    const sh = platform.Shell.detect();
    if (sh != .unknown) {
        shell_mod.ensurePluginPath(sh, allocator) catch {};
    }

    try state.addPlugin(plugin_name, source, "latest");
    std.debug.print("{s}✅{s} Plugin 'dot-{s}' installed\n\n", .{ GREEN, RESET, plugin_name });
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
        std.debug.print("  git clone failed\n", .{});
        return error.GitCloneFailed;
    }

    // Look for the executable: dot-<name> or <name> in the repo root
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

    std.debug.print("  Warning: no executable found in repo, copying repo as-is\n", .{});
}

fn uninstallPlugin(
    allocator: std.mem.Allocator,
    name: []const u8,
    state: *state_mod.State,
) !void {
    if (!state.plugins.contains(name)) {
        std.debug.print("Plugin '{s}' is not installed\n", .{name});
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
    std.debug.print("Removed plugin 'dot-{s}'\n", .{name});
}

fn updatePlugins(
    allocator: std.mem.Allocator,
    name: ?[]const u8,
    state: *state_mod.State,
) !void {
    if (name) |n| {
        const entry = state.plugins.get(n) orelse {
            std.debug.print("Plugin '{s}' not found\n", .{n});
            return;
        };
        try installPlugin(allocator, entry.source_url, state);
    } else {
        var it = state.plugins.iterator();
        while (it.next()) |kv| {
            installPlugin(allocator, kv.value_ptr.*.source_url, state) catch |e| {
                std.debug.print("Failed to update {s}: {}\n", .{ kv.key_ptr.*, e });
            };
        }
    }
}

fn pluginNameFromSource(source: []const u8) []const u8 {
    // Take the last path component, strip .git, strip "dot-" prefix
    const base = std.fs.path.basename(source);
    const stripped = if (std.mem.endsWith(u8, base, ".git")) base[0 .. base.len - 4] else base;
    return if (std.mem.startsWith(u8, stripped, "dot-")) stripped[4..] else stripped;
}

fn printUsage() void {
    std.debug.print(
        \\
        \\Usage: dot plugin <command>
        \\
        \\Commands:
        \\  list                List installed plugins
        \\  install <url|name>  Install a plugin from URL or local path
        \\  uninstall <name>    Remove a plugin
        \\  update [name]       Update one or all plugins
        \\
        \\
    , .{});
}
