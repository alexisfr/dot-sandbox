const std = @import("std");
const tool_mod = @import("../tool.zig");
const state_mod = @import("../state.zig");
const registry = @import("../registry/mod.zig");
const platform = @import("../platform.zig");
const shell_mod = @import("../shell.zig");
const output = @import("../ui/output.zig");

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
) !void {
    if (args.len == 0) {
        std.debug.print("Usage: dot install <tool> [version] [--force]\n", .{});
        std.debug.print("       dot install --group <group> [--force]\n", .{});
        return;
    }

    var force = false;
    var version_arg: ?[]const u8 = null;
    var group_mode = false;
    var group_name: []const u8 = "";
    var tool_name: []const u8 = "";

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--force")) {
            force = true;
        } else if (std.mem.eql(u8, a, "--group") or std.mem.eql(u8, a, "-g")) {
            group_mode = true;
            i += 1;
            if (i < args.len) group_name = args[i];
        } else if (tool_name.len == 0 and !group_mode) {
            tool_name = a;
        } else if (version_arg == null and tool_name.len > 0) {
            version_arg = a;
        }
    }

    if (group_mode) {
        try installGroup(allocator, group_name, force, state);
    } else if (tool_name.len > 0) {
        try installTool(allocator, tool_name, version_arg, force, state);
    } else {
        std.debug.print("Error: no tool or group specified\n", .{});
    }
}

fn installGroup(
    allocator: std.mem.Allocator,
    group_name: []const u8,
    force: bool,
    state: *state_mod.State,
) !void {
    const group = parseGroup(group_name) orelse {
        std.debug.print("Error: unknown group '{s}'\n", .{group_name});
        std.debug.print("Available groups: k8s, cloud, iac, containers, utils, terminal, all\n", .{});
        return;
    };

    var buf: [registry.all_tools.len]*const tool_mod.Tool = undefined;
    var tools: []const *const tool_mod.Tool = &.{};

    if (group_name.len == 3 and std.mem.eql(u8, group_name, "all")) {
        tools = registry.all_tools;
    } else {
        registry.findByGroup(group, &buf, &tools);
    }

    if (tools.len == 0) {
        std.debug.print("No tools found in group '{s}'\n", .{group_name});
        return;
    }

    std.debug.print("Installing group '{s}' ({d} tools)...\n\n", .{ group_name, tools.len });

    for (tools) |t| {
        installTool(allocator, t.id, null, force, state) catch |e| {
            std.debug.print("  Failed to install {s}: {}\n", .{ t.id, e });
        };
    }
}

fn installTool(
    allocator: std.mem.Allocator,
    id: []const u8,
    version_arg: ?[]const u8,
    force: bool,
    state: *state_mod.State,
) !void {
    const t = registry.findById(id) orelse {
        std.debug.print("Error: unknown tool '{s}'\n", .{id});
        std.debug.print("Run 'dot list' to see available tools\n", .{});
        return;
    };

    // Resolve version
    var version: []u8 = undefined;
    var version_owned = false;

    if (version_arg) |v| {
        version = try allocator.dupe(u8, v);
        version_owned = true;
    } else {
        std.debug.print("🔍 Fetching latest version for {s}...\n", .{t.name});
        version = t.version_source.resolve(allocator) catch |e| {
            std.debug.print("Warning: could not fetch version ({s}), using 'latest'\n", .{@errorName(e)});
            version = try allocator.dupe(u8, "latest");
            version_owned = true;
            // avoid double-set below
            version_owned = true;
            return; // fallback handled above
        };
        version_owned = true;
    }
    defer if (version_owned) allocator.free(version);

    // Check system install (not our ~/.local/bin)
    if (!force) {
        if (checkSystemInstall(allocator, t.id)) |sys_path| {
            defer allocator.free(sys_path);
            output.printBox(t.name, version);
            output.printSkipSystem(t.name, sys_path, "unknown", version);
            return;
        }
    }

    // Check if already up to date
    if (!force) {
        if (state.getVersion(t.id)) |installed_ver| {
            if (std.mem.eql(u8, installed_ver, version)) {
                output.printBox(t.name, version);
                output.printAlreadyReady(t.name);
                return;
            }
        }
    }

    // Print install box + summary
    output.printBox(t.name, version);

    const os = platform.Os.current();
    const arch = platform.Arch.current();

    const pkg_line = try std.fmt.allocPrint(allocator, "Package: {s} {s}", .{ t.id, version });
    defer allocator.free(pkg_line);
    const plat_line = try std.fmt.allocPrint(allocator, "Platform: {s}/{s}", .{ os.name(), arch.goName() });
    defer allocator.free(plat_line);
    const src_line = try std.fmt.allocPrint(allocator, "Source: {s}", .{t.homepage});
    defer allocator.free(src_line);
    output.printSummary(&.{ pkg_line, plat_line, src_line });
    std.debug.print("\n", .{});

    output.printStep("Pre-checks", "✓", "Ready");

    // Set up context
    const home = std.posix.getenv("HOME") orelse "/tmp";
    const bin_dir = try std.fs.path.join(allocator, &.{ home, ".local", "bin" });
    defer allocator.free(bin_dir);

    const tmp_dir = try std.fmt.allocPrint(allocator, "/tmp/dot-{s}-{s}", .{ t.id, version });
    defer allocator.free(tmp_dir);

    std.fs.cwd().makePath(tmp_dir) catch {};
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};

    var ctx = tool_mod.InstallContext{
        .allocator = allocator,
        .id = t.id,
        .version = version,
        .os = os,
        .arch = arch,
        .bin_dir = bin_dir,
        .tmp_dir = tmp_dir,
    };

    // Execute strategy
    output.printStep("Downloading", "→", "");
    t.strategy.execute(&ctx) catch |e| {
        output.printStep("Installation", "✗", @errorName(e));
        output.printError("Installation failed");
        return e;
    };
    output.printStep("Installation", "✓", bin_dir);

    // Shell integration
    const sh = platform.Shell.detect();
    if (sh != .unknown) {
        if (t.shell_completions) |completions| {
            if (completions.forShell(sh)) |config| {
                shell_mod.ensureSourced(sh, allocator) catch {};
                shell_mod.addSection(sh, t.id, config, allocator) catch {};
                output.printStep("Shell integration", "✓", sh.name());
            } else {
                output.printStep("Shell integration", "-", "no config for this shell");
            }
        }
    }

    // Post-install
    if (t.post_install) |pi| {
        switch (pi) {
            .helm_plugins => |plugins| {
                output.printStep("Plugins", "→", "");
                installHelmPlugins(allocator, plugins);
                output.printStep("Plugins", "✓", "");
            },
            .none => {},
        }
    }

    // Update state
    try state.addTool(t.id, version, @tagName(t.strategy));

    // Success
    output.printSuccess(t.name, null);
    if (t.quick_start.len > 0) output.printQuickStart(t.quick_start);
    if (t.resources.len > 0) {
        var res_items: std.ArrayList([]const u8) = .empty;
        defer res_items.deinit(allocator);
        for (t.resources) |r| {
            try res_items.append(allocator, try std.fmt.allocPrint(allocator, "{s}: {s}", .{ r.label, r.url }));
        }
        output.printResources(res_items.items);
        for (res_items.items) |item| allocator.free(item);
    }
}

fn installHelmPlugins(allocator: std.mem.Allocator, plugins: []const []const u8) void {
    for (plugins) |plugin_url| {
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "helm", "plugin", "install", plugin_url },
        }) catch continue;
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.term.Exited == 0) {
            std.debug.print("   ✓ {s}\n", .{plugin_url});
        } else {
            std.debug.print("   - {s} (skipped or already installed)\n", .{plugin_url});
        }
    }
}

/// Returns owned path string if tool is found in system PATH outside ~/.local/bin.
fn checkSystemInstall(allocator: std.mem.Allocator, id: []const u8) ?[]u8 {
    const home = std.posix.getenv("HOME") orelse return null;
    const our_path = std.fs.path.join(allocator, &.{ home, ".local", "bin", id }) catch return null;
    defer allocator.free(our_path);

    const cmd_str = std.fmt.allocPrint(allocator, "type -aP {s} 2>/dev/null | head -5", .{id}) catch return null;
    defer allocator.free(cmd_str);

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "sh", "-c", cmd_str },
    }) catch return null;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) return null;

    var lines = std.mem.splitScalar(u8, std.mem.trim(u8, result.stdout, "\n"), '\n');
    while (lines.next()) |line| {
        const path = std.mem.trim(u8, line, " \r");
        if (path.len == 0) continue;
        if (std.mem.eql(u8, path, our_path)) continue;
        return allocator.dupe(u8, path) catch null;
    }
    return null;
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
