const std = @import("std");
const tool_mod = @import("../tool.zig");
const state_mod = @import("../state.zig");
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

const HELP =
    \\Usage: dot install <tool> [version] [--force]
    \\       dot install --group <group> [--force]
    \\
    \\Install a tool from the repository.
    \\
    \\Arguments:
    \\  <tool>         Tool ID to install (e.g. helm, kubectl)
    \\  [version]      Pin to a specific version (e.g. 1.8.0)
    \\  --group, -g    Install all tools in a group
    \\
    \\Options:
    \\  --force        Force reinstall, even if already up to date
    \\  --help, -h     Show this help
    \\
    \\Groups:  k8s, cloud, iac, containers, utils, terminal, all
    \\
    \\Pinning:
    \\  Specifying a version pins the tool — it will be skipped by
    \\  'dot upgrade' unless --force is used.
    \\
    \\Examples:
    \\  dot install helm
    \\  dot install terraform 1.8.0
    \\  dot install --group k8s
    \\  dot install helm --force
    \\
;

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
    tools: []const tool_mod.Tool,
) !void {
    if (args.len == 0) {
        output.printRaw(HELP);
        return;
    }

    for (args) |a| {
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            output.printRaw(HELP);
            return;
        }
    }

    const parsed = parseInstallArgs(args);

    if (parsed.group_mode) {
        try installGroup(allocator, parsed.group_name, parsed.force, state, tools);
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
        try installTool(allocator, parsed.tool_name, parsed.version_arg, parsed.force, state, tools);
    } else {
        output.printError("no tool or group specified");
    }
}

fn installGroup(
    allocator: std.mem.Allocator,
    group_name: []const u8,
    force: bool,
    state: *state_mod.State,
    tools: []const tool_mod.Tool,
) !void {
    const is_all = std.mem.eql(u8, group_name, "all");
    if (!is_all and parseGroup(group_name) == null) {
        printUnknownGroup(group_name);
        return;
    }

    var group_tools: std.ArrayList(tool_mod.Tool) = .empty;
    defer group_tools.deinit(allocator);

    if (is_all) {
        try group_tools.appendSlice(allocator, tools);
    } else {
        const group = parseGroup(group_name).?;
        for (tools) |t| {
            for (t.groups) |g| {
                if (g == group) {
                    try group_tools.append(allocator, t);
                    break;
                }
            }
        }
    }

    if (group_tools.items.len == 0) {
        output.printFmt("No tools found in group '{s}'\n", .{group_name});
        return;
    }

    printGroupBanner(group_name, group_tools.items.len);

    for (group_tools.items) |t| {
        installTool(allocator, t.id, null, force, state, tools) catch |e| {
            printGroupToolError(t.id, e);
        };
    }
}

fn installTool(
    allocator: std.mem.Allocator,
    id: []const u8,
    version_arg: ?[]const u8,
    force: bool,
    state: *state_mod.State,
    tools: []const tool_mod.Tool,
) !void {
    var found: ?tool_mod.Tool = null;
    for (tools) |t| {
        if (std.mem.eql(u8, t.id, id)) {
            found = t;
            break;
        }
    }
    const t = found orelse {
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
        printFetchingVersion(t.name);
        version = t.version_source.resolve(allocator) catch |e| {
            printVersionFetchWarning(@errorName(e));
            version = try allocator.dupe(u8, "latest");
            version_owned = true;
            // avoid double-set below
            version_owned = true;
            return; // fallback handled above
        };
        version_owned = true;
    }
    defer if (version_owned) allocator.free(version);

    // Skip pinned tools unless forced
    if (!force and version_arg == null) {
        if (state.isPinned(t.id)) {
            const pinned_ver = state.getVersion(t.id) orelse "pinned";
            printBox(t.name, pinned_ver);
            printPinnedSkip(t.name, pinned_ver);
            return;
        }
    }

    // Check system install (not our ~/.local/bin)
    if (!force) {
        if (checkSystemInstall(allocator, t.id)) |sys_path| {
            defer allocator.free(sys_path);
            printBox(t.name, version);
            printSkipSystem(t.name, sys_path, "unknown", version);
            return;
        }
    }

    // Check if already up to date
    if (!force) {
        if (state.getVersion(t.id)) |installed_ver| {
            if (std.mem.eql(u8, installed_ver, version)) {
                printBox(t.name, version);
                printAlreadyReady(t.name);
                return;
            }
        }
    }

    // Print install box + summary
    printBox(t.name, version);

    const os = platform.Os.current();
    const arch = platform.Arch.current();

    const pkg_line = try std.fmt.allocPrint(allocator, "Package: {s} {s}", .{ t.id, version });
    defer allocator.free(pkg_line);
    const plat_line = try std.fmt.allocPrint(allocator, "Platform: {s}/{s}", .{ os.name(), arch.goName() });
    defer allocator.free(plat_line);
    const src_line = try std.fmt.allocPrint(allocator, "Source: {s}", .{t.homepage});
    defer allocator.free(src_line);
    printSummary(&.{ pkg_line, plat_line, src_line });

    output.printStep("Pre-checks", "✓", "Ready");

    // Brew install path: preferred when brew is available and tool declares a formula
    var used_brew = false;
    if (t.brew_formula) |formula| {
        if (platform.PackageManager.brew.isAvailable()) {
            output.printStep("Brew", "→", formula);
            brewInstall(allocator, formula, force) catch |e| {
                output.printStep("Brew", output.SYM_FAIL, @errorName(e));
                output.printError("brew install failed");
                return e;
            };
            output.printStep("Brew", output.SYM_OK, formula);
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
            output.printStep("Installation", output.SYM_FAIL, @errorName(e));
            output.printError("Installation failed");
            return e;
        };
        output.printStep("Installation", output.SYM_OK, bin_dir);

        // Shell integration (brew handles its own PATH and completions)
        const sh = platform.Shell.detect();
        if (sh != .unknown) {
            var section: std.ArrayList(u8) = .empty;
            defer section.deinit(allocator);

            if (t.shell_completions) |completions| {
                if (completions.forShell(sh)) |comp_cmd| {
                    try section.appendSlice(allocator, comp_cmd);
                }
            }

            for (t.aliases) |alias_name| {
                if (section.items.len > 0) try section.append(allocator, '\n');
                const alias_line = try std.fmt.allocPrint(allocator, "alias {s}={s}", .{ alias_name, t.id });
                defer allocator.free(alias_line);
                try section.appendSlice(allocator, alias_line);
            }

            if (section.items.len > 0) {
                shell_mod.ensureSourced(sh, allocator) catch {};
                shell_mod.addSection(sh, t.id, section.items, allocator) catch {};
                output.printStep("Shell integration", output.SYM_OK, sh.name());
            }
        }
    }

    // Post-install commands — only on fresh installs, not upgrades (non-fatal)
    if (!state.isInstalled(t.id) and t.post_install.len > 0) {
        output.printStep("Post-install", "→", "");
        for (t.post_install) |cmd| {
            const wrapped = try std.fmt.allocPrint(allocator, "export PATH=\"$HOME/.local/bin:$PATH\"; {s}", .{cmd});
            defer allocator.free(wrapped);
            const result = std.process.Child.run(.{
                .allocator = allocator,
                .argv = &.{ "sh", "-c", wrapped },
            }) catch |e| {
                output.printFmt("  {s}✗{s} {s} ({s})\n", .{ output.RED, output.RESET, cmd, @errorName(e) });
                continue;
            };
            defer allocator.free(result.stdout);
            defer allocator.free(result.stderr);
            if (result.term.Exited == 0) {
                output.printFmt("  {s}✓{s} {s}\n", .{ output.GREEN, output.RESET, cmd });
            } else {
                output.printFmt("  {s}✗{s} {s}\n", .{ output.RED, output.RESET, cmd });
            }
        }
    }

    // Post-upgrade commands — only when upgrading an already-installed tool (non-fatal)
    if (state.isInstalled(t.id) and t.post_upgrade.len > 0) {
        output.printStep("Post-upgrade", "→", "");
        for (t.post_upgrade) |cmd| {
            const wrapped = try std.fmt.allocPrint(allocator, "export PATH=\"$HOME/.local/bin:$PATH\"; {s}", .{cmd});
            defer allocator.free(wrapped);
            const result = std.process.Child.run(.{
                .allocator = allocator,
                .argv = &.{ "sh", "-c", wrapped },
            }) catch |e| {
                output.printFmt("  {s}✗{s} {s} ({s})\n", .{ output.RED, output.RESET, cmd, @errorName(e) });
                continue;
            };
            defer allocator.free(result.stdout);
            defer allocator.free(result.stderr);
            if (result.term.Exited == 0) {
                output.printFmt("  {s}✓{s} {s}\n", .{ output.GREEN, output.RESET, cmd });
            } else {
                output.printFmt("  {s}✗{s} {s}\n", .{ output.RED, output.RESET, cmd });
            }
        }
    }

    // Update state — pin if the user specified an explicit version
    const method = if (used_brew) "brew" else @tagName(t.strategy);
    try state.addTool(t.id, version, method, version_arg != null);

    // Success
    printSuccess(t.name, null);
    if (t.quick_start.len > 0) printQuickStart(t.quick_start);
    if (t.resources.len > 0) {
        var res_items: std.ArrayList([]const u8) = .empty;
        defer res_items.deinit(allocator);
        for (t.resources) |r| {
            try res_items.append(allocator, try std.fmt.allocPrint(allocator, "{s}: {s}", .{ r.label, r.url }));
        }
        printResources(res_items.items);
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

pub fn parseGroup(name: []const u8) ?tool_mod.Group {
    if (std.mem.eql(u8, name, "k8s")) return .k8s;
    if (std.mem.eql(u8, name, "cloud")) return .cloud;
    if (std.mem.eql(u8, name, "iac")) return .iac;
    if (std.mem.eql(u8, name, "containers")) return .containers;
    if (std.mem.eql(u8, name, "utils")) return .utils;
    if (std.mem.eql(u8, name, "terminal")) return .terminal;
    return null;
}

// ─── Install-specific print functions ─────────────────────────────────────────

fn printBox(tool: []const u8, version: []const u8) void {
    const inner = 48;
    std.debug.print("{s}+", .{output.CYAN});
    for (0..inner) |_| std.debug.print("-", .{});
    std.debug.print("+{s}\n", .{output.RESET});

    const title_len = tool.len + 1 + version.len + " Installation".len + 1;
    const padding = if (inner > title_len + 2) inner - title_len - 2 else 0;
    std.debug.print("{s}|{s} {s}{s}{s} {s} Installation", .{ output.CYAN, output.RESET, output.BOLD, tool, output.RESET, version });
    for (0..padding) |_| std.debug.print(" ", .{});
    std.debug.print(" {s}|{s}\n", .{ output.CYAN, output.RESET });

    std.debug.print("{s}+", .{output.CYAN});
    for (0..inner) |_| std.debug.print("-", .{});
    std.debug.print("+{s}\n", .{output.RESET});
}

fn printSummary(items: []const []const u8) void {
    std.debug.print("\n{s}{s}{s} {s}Summary:{s}\n", .{ output.CYAN, output.SYM_LIST, output.RESET, output.BOLD, output.RESET });
    for (items) |item| {
        std.debug.print("  • {s}\n", .{item});
    }
    std.debug.print("\n", .{});
}

fn printSuccess(tool: []const u8, duration_s: ?u64) void {
    if (duration_s) |d| {
        std.debug.print("\n{s}{s}{s} {s}{s}{s} installed in {d}s!\n\n", .{
            output.GREEN, output.SYM_CHECK, output.RESET, output.BOLD, tool, output.RESET, d,
        });
    } else {
        std.debug.print("\n{s}{s}{s} {s}{s}{s} installed!\n\n", .{
            output.GREEN, output.SYM_CHECK, output.RESET, output.BOLD, tool, output.RESET,
        });
    }
}

fn printPinnedSkip(tool: []const u8, version: []const u8) void {
    std.debug.print("{s}{s}{s} {s}{s}{s} is pinned at {s} — skipping\n", .{ output.CYAN, output.SYM_PIN, output.RESET, output.BOLD, tool, output.RESET, version });
    std.debug.print("   To upgrade anyway: dot install {s} --force\n", .{tool});
}

fn printAlreadyReady(tool: []const u8) void {
    std.debug.print("\n{s}{s}{s} {s}{s}{s} ready!\n\n", .{ output.GREEN, output.SYM_CHECK, output.RESET, output.BOLD, tool, output.RESET });
}

fn printQuickStart(cmds: []const []const u8) void {
    std.debug.print("{s}{s}{s} {s}Quick Start:{s}\n", .{ output.CYAN, output.SYM_BOOKS, output.RESET, output.BOLD, output.RESET });
    for (cmds) |cmd| {
        std.debug.print("  $ {s}\n", .{cmd});
    }
    std.debug.print("\n", .{});
}

fn printResources(items: []const []const u8) void {
    std.debug.print("{s}{s}{s} {s}Resources:{s}\n", .{ output.CYAN, output.SYM_LINK, output.RESET, output.BOLD, output.RESET });
    for (items) |item| {
        std.debug.print("  • {s}\n", .{item});
    }
}

fn printSkipSystem(tool: []const u8, path: []const u8, sys_ver: []const u8, latest: []const u8) void {
    std.debug.print("\n{s}{s}{s}  {s}{s}{s} detected via system package manager\n\n", .{
        output.YELLOW, output.SYM_WARN, output.RESET, output.BOLD, tool, output.RESET,
    });
    std.debug.print("  Location: {s}\n", .{path});
    std.debug.print("  Version:  {s}\n", .{sys_ver});
    std.debug.print("  Latest:   {s}\n", .{latest});
    std.debug.print("\n  To install dot's version, run: dot install {s} --force\n\n", .{tool});
}

fn printFetchingVersion(name: []const u8) void {
    std.debug.print("{s} Fetching latest version for {s}...\n", .{ output.SYM_SEARCH, name });
}

fn printVersionFetchWarning(err_name: []const u8) void {
    std.debug.print("{s}Warning:{s} could not fetch version ({s}), using 'latest'\n", .{ output.YELLOW, output.RESET, err_name });
}

fn printUnknownGroup(name: []const u8) void {
    std.debug.print("{s}Error:{s} unknown group '{s}'\n", .{ output.RED, output.RESET, name });
    std.debug.print("Available groups: k8s, cloud, iac, containers, utils, terminal, all\n", .{});
}

fn printGroupToolError(id: []const u8, err: anyerror) void {
    std.debug.print("  {s}Failed{s} to install {s}: {s}\n", .{ output.RED, output.RESET, id, @errorName(err) });
}

fn printGroupBanner(group_name: []const u8, count: usize) void {
    std.debug.print("Installing group '{s}' ({d} tools)...\n\n", .{ group_name, count });
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
