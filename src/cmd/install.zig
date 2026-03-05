const std = @import("std");
const tool_mod = @import("../tool.zig");
const state_mod = @import("../state.zig");
const registry = @import("../registry/mod.zig");
const platform = @import("../platform.zig");
const shell_mod = @import("../shell.zig");
const output = @import("../ui/output.zig");
const validate = @import("../validate.zig");

pub const InstallArgs = struct {
    force: bool = false,
    group_mode: bool = false,
    group_name: []const u8 = "",
    tool_name: []const u8 = "",
    version_arg: ?[]const u8 = null,
};

pub fn parseInstallArgs(args: []const []const u8) InstallArgs {
    var result = InstallArgs{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--force")) {
            result.force = true;
        } else if (std.mem.eql(u8, a, "--group") or std.mem.eql(u8, a, "-g")) {
            result.group_mode = true;
            i += 1;
            if (i < args.len) result.group_name = args[i];
        } else if (result.tool_name.len == 0 and !result.group_mode) {
            result.tool_name = a;
        } else if (result.version_arg == null and result.tool_name.len > 0) {
            result.version_arg = a;
        }
    }
    return result;
}

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
) !void {
    if (args.len == 0) {
        output.printInstallUsage();
        return;
    }

    const parsed = parseInstallArgs(args);

    if (parsed.group_mode) {
        try installGroup(allocator, parsed.group_name, parsed.force, state);
    } else if (parsed.tool_name.len > 0) {
        if (!validate.isValidToolId(parsed.tool_name)) {
            output.printError("invalid tool name");
            return;
        }
        if (parsed.version_arg) |v| {
            if (!validate.isValidVersion(v)) {
                output.printError("invalid version string");
                return;
            }
        }
        try installTool(allocator, parsed.tool_name, parsed.version_arg, parsed.force, state);
    } else {
        output.printError("no tool or group specified");
    }
}

fn installGroup(
    allocator: std.mem.Allocator,
    group_name: []const u8,
    force: bool,
    state: *state_mod.State,
) !void {
    const group = parseGroup(group_name) orelse {
        output.printUnknownGroup(group_name);
        return;
    };

    var buf_arr: [registry.all_tools.len]*const tool_mod.Tool = undefined;
    const buf: []*const tool_mod.Tool = &buf_arr;
    var tools: []const *const tool_mod.Tool = &.{};

    if (group_name.len == 3 and std.mem.eql(u8, group_name, "all")) {
        tools = registry.all_tools;
    } else {
        registry.findByGroup(group, buf, &tools);
    }

    if (tools.len == 0) {
        output.printNoToolsInGroup(group_name);
        return;
    }

    output.printGroupInstall(group_name, tools.len);

    for (tools) |t| {
        installTool(allocator, t.id, null, force, state) catch |e| {
            output.printGroupToolError(t.id, e);
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
        output.printUnknownTool(id);
        return;
    };

    // Resolve version
    var version: []u8 = undefined;
    var version_owned = false;

    if (version_arg) |v| {
        version = try allocator.dupe(u8, v);
        version_owned = true;
    } else {
        output.printFetchingVersion(t.name);
        version = t.version_source.resolve(allocator) catch |e| {
            output.printVersionFetchWarning(@errorName(e));
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

    output.printStep("Pre-checks", "✓", "Ready");

    // Brew install path: preferred when brew is available and tool declares a formula
    var used_brew = false;
    if (t.brew_formula) |formula| {
        if (platform.PackageManager.brew.isAvailable()) {
            output.printStep("Brew", "→", formula);
            brewInstall(allocator, formula, force) catch |e| {
                output.printStep("Brew", "✗", @errorName(e));
                output.printError("brew install failed");
                return e;
            };
            output.printStep("Brew", "✓", formula);
            used_brew = true;
        }
    }

    if (!used_brew) {
        // Native install path: download, extract, copy binary
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

        output.printStep("Downloading", "→", "");
        t.strategy.execute(&ctx) catch |e| {
            output.printStep("Installation", "✗", @errorName(e));
            output.printError("Installation failed");
            return e;
        };
        output.printStep("Installation", "✓", bin_dir);

        // Shell integration (brew handles its own PATH and completions)
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
    }

    // Post-install runs regardless of install method (e.g. helm plugins)
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
    const method = if (used_brew) "brew" else @tagName(t.strategy);
    try state.addTool(t.id, version, method);

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

fn brewInstall(allocator: std.mem.Allocator, formula: []const u8, force: bool) !void {
    // `brew reinstall` always reinstalls; `brew install` is a no-op if already present
    const brew_cmd: []const u8 = if (force) "reinstall" else "install";
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "brew", brew_cmd, formula },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        const msg = std.mem.trim(u8, result.stderr, " \n\r\t");
        if (msg.len > 0) output.printDetail(msg);
        return error.BrewInstallFailed;
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

        output.printHelmPlugin(plugin_url, result.term.Exited == 0);
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

// ─── Tests ────────────────────────────────────────────────────────────────────

test "parseInstallArgs: tool name only" {
    const a = parseInstallArgs(&.{"helm"});
    try std.testing.expectEqualStrings("helm", a.tool_name);
    try std.testing.expect(a.version_arg == null);
    try std.testing.expect(!a.force);
    try std.testing.expect(!a.group_mode);
}

test "parseInstallArgs: tool name with version" {
    const a = parseInstallArgs(&.{ "helm", "3.15.0" });
    try std.testing.expectEqualStrings("helm", a.tool_name);
    try std.testing.expectEqualStrings("3.15.0", a.version_arg.?);
}

test "parseInstallArgs: --force flag" {
    const a = parseInstallArgs(&.{ "--force", "helm" });
    try std.testing.expect(a.force);
    try std.testing.expectEqualStrings("helm", a.tool_name);
}

test "parseInstallArgs: --force after tool" {
    const a = parseInstallArgs(&.{ "helm", "--force" });
    // --force before tool_name is set is fine; after tool_name is set, --force
    // isn't parsed as a special flag in current logic — it would be version_arg.
    // This test documents current behavior.
    try std.testing.expectEqualStrings("helm", a.tool_name);
}

test "parseInstallArgs: --group flag" {
    const a = parseInstallArgs(&.{ "--group", "k8s" });
    try std.testing.expect(a.group_mode);
    try std.testing.expectEqualStrings("k8s", a.group_name);
    try std.testing.expect(!a.force);
}

test "parseInstallArgs: -g shorthand" {
    const a = parseInstallArgs(&.{ "-g", "iac" });
    try std.testing.expect(a.group_mode);
    try std.testing.expectEqualStrings("iac", a.group_name);
}

test "parseInstallArgs: --force with group" {
    const a = parseInstallArgs(&.{ "--force", "--group", "cloud" });
    try std.testing.expect(a.force);
    try std.testing.expect(a.group_mode);
    try std.testing.expectEqualStrings("cloud", a.group_name);
}

test "parseInstallArgs: empty args" {
    const a = parseInstallArgs(&.{});
    try std.testing.expectEqualStrings("", a.tool_name);
    try std.testing.expect(!a.group_mode);
    try std.testing.expect(!a.force);
}

test "parseGroup: known groups" {
    try std.testing.expectEqual(tool_mod.Group.k8s, parseGroup("k8s").?);
    try std.testing.expectEqual(tool_mod.Group.cloud, parseGroup("cloud").?);
    try std.testing.expectEqual(tool_mod.Group.iac, parseGroup("iac").?);
    try std.testing.expectEqual(tool_mod.Group.containers, parseGroup("containers").?);
    try std.testing.expectEqual(tool_mod.Group.utils, parseGroup("utils").?);
    try std.testing.expectEqual(tool_mod.Group.terminal, parseGroup("terminal").?);
}

test "parseGroup: unknown groups return null" {
    try std.testing.expect(parseGroup("unknown") == null);
    try std.testing.expect(parseGroup("") == null);
    try std.testing.expect(parseGroup("K8S") == null); // case-sensitive
    try std.testing.expect(parseGroup("all") == null); // "all" is handled separately
}
