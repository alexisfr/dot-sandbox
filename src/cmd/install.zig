const std = @import("std");
const tool_mod = @import("../tool.zig");
const state_mod = @import("../state.zig");
const platform = @import("../platform.zig");
const shell_mod = @import("../shell.zig");
const output = @import("../ui/output.zig");
const validate = @import("../validate.zig");
const http = @import("../http.zig");
const progress_mod = @import("../ui/progress.zig");

fn progressCbFn(ctx: *anyopaque, done: u64, total: ?u64) void {
    const bar: *progress_mod.ProgressBar = @ptrCast(@alignCast(ctx));
    bar.update(done, total, "");
}

pub const InstallArgs = struct {
    force: bool = false,
    group_mode: bool = false,
    group_name: []const u8 = "",
    tool_name: []const u8 = "",
    version_arg: ?[]const u8 = null,
};

pub fn parseInstallArgs(args: []const []const u8) InstallArgs {
    var result = InstallArgs{};
    var idx: usize = 0;
    while (idx < args.len) : (idx += 1) {
        const arg = args[idx];
        if (std.mem.eql(u8, arg, "--force")) {
            result.force = true;
        } else if (std.mem.eql(u8, arg, "--group") or std.mem.eql(u8, arg, "-g")) {
            result.group_mode = true;
            idx += 1;
            if (idx < args.len) result.group_name = args[idx];
        } else if (result.tool_name.len == 0 and !result.group_mode) {
            result.tool_name = arg;
        } else if (result.version_arg == null and result.tool_name.len > 0) {
            result.version_arg = arg;
        }
    }
    return result;
}

const help =
    \\Usage: dot install <tool> [version] [--force]
    \\       dot install --group <group> [--force]
    \\
    \\Install a tool from the repository.
    \\
    \\Arguments:
    \\  <tool>         Tool ID to install (e.g. helm, kubectl)
    \\  [version]      Pin to a specific version (e.g. 1.8.0)
    \\
    \\Options:
    \\  --group, -g    Install all tools in a group
    \\  --force        Force reinstall, even if already installed
    \\  --help, -h     Show this help
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

fn printAvailableGroups(tools: []const tool_mod.Tool) void {
    const max_groups = 10;
    const n_fields = @typeInfo(tool_mod.Group).@"enum".fields.len;
    var seen = [_]bool{false} ** n_fields;

    for (tools) |t| {
        for (t.groups) |g| {
            seen[@intFromEnum(g)] = true;
        }
    }

    std.debug.print("\nGroups: ", .{});
    var shown: usize = 0;
    inline for (std.meta.fields(tool_mod.Group)) |field| {
        if (shown >= max_groups) break;
        if (seen[field.value]) {
            if (shown > 0) std.debug.print(", ", .{});
            std.debug.print("{s}", .{field.name});
            shown += 1;
        }
    }
    if (shown > 0) std.debug.print(", all", .{});
    std.debug.print("\n\n", .{});
}

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
    tools: []const tool_mod.Tool,
) !void {
    if (args.len == 0) {
        output.printRaw(help);
        printAvailableGroups(tools);
        return;
    }

    for (args) |a| {
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            output.printRaw(help);
            printAvailableGroups(tools);
            return;
        }
    }

    const parsed = parseInstallArgs(args);

    const is_group_name = std.mem.eql(u8, parsed.tool_name, "all") or
        parseGroup(parsed.tool_name) != null;

    if (parsed.group_mode or (!parsed.group_mode and is_group_name)) {
        const grp = if (parsed.group_mode) parsed.group_name else parsed.tool_name;
        try installGroup(allocator, grp, parsed.force, state, tools);
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
    var group_tools: std.ArrayList(tool_mod.Tool) = .empty;
    defer group_tools.deinit(allocator);

    if (is_all) {
        try group_tools.appendSlice(allocator, tools);
    } else {
        const group = parseGroup(group_name) orelse {
            printUnknownGroup(group_name);
            return;
        };
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

    for (group_tools.items, 0..) |t, i| {
        printGroupToolSeparator(t.name, i + 1, group_tools.items.len);
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
    for (tools) |entry| {
        if (std.mem.eql(u8, entry.id, id)) {
            found = entry;
            break;
        }
    }
    const tool = found orelse {
        output.printUnknownTool(id);
        if (closestTool(id, tools)) |suggestion| {
            std.debug.print("Did you mean '{s}'?\n", .{suggestion});
        }
        return;
    };

    // Resolve version
    var version: []u8 = undefined;
    var version_owned = false;

    if (version_arg) |v| {
        version = try allocator.dupe(u8, v);
        version_owned = true;
    } else {
        printFetchingVersion(tool.name);
        version = tool.version_source.resolve(allocator) catch |e| blk: {
            printVersionFetchWarning(@errorName(e));
            break :blk try allocator.dupe(u8, "latest");
        };
        version_owned = true;
    }
    defer if (version_owned) allocator.free(version);

    // Skip pinned tools unless forced
    if (!force and version_arg == null) {
        if (state.isPinned(tool.id)) {
            const pinned_ver = state.getVersion(tool.id) orelse "pinned";
            printPinnedSkip(tool.name, tool.id, pinned_ver);
            return;
        }
    }

    // Check system install (not our ~/.local/bin) — only when dot doesn't already manage this tool.
    // If dot already owns it (it's in state), the user already resolved the conflict; don't warn again.
    if (!force and !state.isInstalled(tool.id)) {
        if (checkSystemInstall(allocator, tool.id)) |sys_path| {
            defer allocator.free(sys_path);
            printSkipSystem(tool.name, sys_path, "unknown", version);
            return;
        }
    }

    // Check if already up to date
    if (!force) {
        if (state.getVersion(tool.id)) |installed_ver| {
            if (std.mem.eql(u8, installed_ver, version)) {
                printAlreadyReady(tool.name, installed_ver);
                return;
            }
        }
    }

    const operating_system = platform.OperatingSystem.current();
    const arch = platform.Arch.current();

    printInstallHeader(tool.name, version, version_arg != null);

    // Brew install path: preferred when brew is available and tool declares a formula
    var used_brew = false;
    if (tool.brew_formula) |formula| {
        if (platform.PackageManager.brew.isAvailable()) {
            output.printStep("Brew", output.sym_arrow, formula);
            brewInstall(allocator, formula, force) catch |e| {
                output.printStep("Brew", output.sym_fail, @errorName(e));
                output.printError("brew install failed");
                return e;
            };
            output.printStep("Brew", output.sym_ok, formula);
            used_brew = true;
        }
    }

    if (!used_brew) {
        // Native install path: download, extract, copy binary
        const home = std.posix.getenv("HOME") orelse "/tmp";
        const bin_dir = try std.fs.path.join(allocator, &.{ home, ".local", "bin" });
        defer allocator.free(bin_dir);

        const tmp_dir = try std.fmt.allocPrint(allocator, "/tmp/dot-{s}-{s}", .{ tool.id, version });
        defer allocator.free(tmp_dir);

        std.fs.cwd().makePath(tmp_dir) catch {};
        defer std.fs.cwd().deleteTree(tmp_dir) catch {};

        var bar = progress_mod.ProgressBar{ .step = "Downloading" };
        var ctx = tool_mod.InstallContext{
            .allocator = allocator,
            .tool_id = tool.id,
            .version = version,
            .operating_system = operating_system,
            .architecture = arch,
            .bin_dir = bin_dir,
            .tmp_dir = tmp_dir,
            .progress = http.ProgressCallback{ .context = &bar, .func = progressCbFn },
        };

        tool.strategy.execute(&ctx) catch |e| {
            bar.finish();
            output.printStep("Installation", output.sym_fail, @errorName(e));
            output.printError("Installation failed");
            return e;
        };
        bar.finish();
        output.printStep("Installation", output.sym_ok, bin_dir);
    }

    // Shell integration (always, regardless of install method)
    _ = writeShellIntegration(&tool, allocator);

    // Post-install commands — only on fresh installs, not upgrades (non-fatal)
    if (!state.isInstalled(tool.id) and tool.post_install.len > 0) {
        output.printStep("Post-install", output.sym_arrow, "");
        for (tool.post_install) |cmd| {
            const wrapped = try std.fmt.allocPrint(allocator, "export PATH=\"$HOME/.local/bin:$PATH\"; {s}", .{cmd});
            defer allocator.free(wrapped);
            const result = std.process.Child.run(.{
                .allocator = allocator,
                .argv = &.{ "sh", "-c", wrapped },
            }) catch |e| {
                output.printFmt("  {s}{s}{s} {s} ({s})\n", .{ output.red, output.sym_fail, output.reset, cmd, @errorName(e) });
                continue;
            };
            defer allocator.free(result.stdout);
            defer allocator.free(result.stderr);
            if (result.term.Exited == 0) {
                output.printFmt("  {s}{s}{s} {s}\n", .{ output.green, output.sym_ok, output.reset, cmd });
            } else {
                output.printFmt("  {s}{s}{s} {s}\n", .{ output.red, output.sym_fail, output.reset, cmd });
            }
        }
    }

    // Post-upgrade commands — only when upgrading an already-installed tool (non-fatal)
    if (state.isInstalled(tool.id) and tool.post_upgrade.len > 0) {
        output.printStep("Post-upgrade", output.sym_arrow, "");
        for (tool.post_upgrade) |cmd| {
            const wrapped = try std.fmt.allocPrint(allocator, "export PATH=\"$HOME/.local/bin:$PATH\"; {s}", .{cmd});
            defer allocator.free(wrapped);
            const result = std.process.Child.run(.{
                .allocator = allocator,
                .argv = &.{ "sh", "-c", wrapped },
            }) catch |e| {
                output.printFmt("  {s}{s}{s} {s} ({s})\n", .{ output.red, output.sym_fail, output.reset, cmd, @errorName(e) });
                continue;
            };
            defer allocator.free(result.stdout);
            defer allocator.free(result.stderr);
            if (result.term.Exited == 0) {
                output.printFmt("  {s}{s}{s} {s}\n", .{ output.green, output.sym_ok, output.reset, cmd });
            } else {
                output.printFmt("  {s}{s}{s} {s}\n", .{ output.red, output.sym_fail, output.reset, cmd });
            }
        }
    }

    // Update state — pin if the user specified an explicit version
    const method = if (used_brew) "brew" else @tagName(tool.strategy);
    try state.addTool(tool.id, version, method, version_arg != null);

    // Success
    printSuccess(tool.name, null);
    if (tool.quick_start.len > 0) printQuickStart(tool.quick_start);
    if (tool.resources.len > 0) {
        var res_items: std.ArrayList([]const u8) = .empty;
        defer res_items.deinit(allocator);
        for (tool.resources) |r| {
            try res_items.append(allocator, try std.fmt.allocPrint(allocator, "{s}: {s}", .{ r.label, r.url }));
        }
        printResources(res_items.items);
        for (res_items.items) |item| allocator.free(item);
    }
}

/// Write shell completions and aliases for a tool. Returns true if anything was written.
/// Wrap a completion command in a shell-appropriate existence guard so that
/// sourcing the integration file silently skips missing binaries.
fn guardedCompletion(sh: platform.Shell, id: []const u8, cmd: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return switch (sh) {
        .fish => std.fmt.allocPrint(allocator, "if command -q {s}\n    {s}\nend", .{ id, cmd }),
        .bash, .zsh => std.fmt.allocPrint(allocator, "command -v {s} >/dev/null 2>&1 && {s}", .{ id, cmd }),
        // Currently unreachable: writeShellIntegration returns early for .unknown
        .unknown => allocator.dupe(u8, cmd),
    };
}

fn writeShellIntegration(t: *const tool_mod.Tool, allocator: std.mem.Allocator) bool {
    const shell_type = platform.Shell.detect();
    if (shell_type == .unknown) return false;

    var section: std.ArrayList(u8) = .empty;
    defer section.deinit(allocator);

    if (t.shell_completions) |completions| {
        if (completions.forShell(shell_type)) |comp_cmd| {
            const guarded = guardedCompletion(shell_type, t.id, comp_cmd, allocator) catch return false;
            defer allocator.free(guarded);
            section.appendSlice(allocator, guarded) catch return false;
        }
    }

    for (t.aliases) |alias_name| {
        if (section.items.len > 0) section.append(allocator, '\n') catch return false;
        const alias_line = std.fmt.allocPrint(allocator, "alias {s}={s}", .{ alias_name, t.id }) catch return false;
        defer allocator.free(alias_line);
        section.appendSlice(allocator, alias_line) catch return false;

        // Delegate completions to the original command so tab-completion works with the alias.
        // Fish: `complete -c <alias> -w <id>` inherits all completions via --wraps.
        // Zsh:  `compdef <alias>=<id>` delegates the completion function.
        // Bash: the generated completion function name (e.g. __start_kubectl) isn't predictable
        //       enough for a generic solution, so bash users get the alias but not the completions.
        const comp_delegation: ?[]const u8 = switch (shell_type) {
            .fish => std.fmt.allocPrint(allocator, "\ncomplete -c {s} -w {s}", .{ alias_name, t.id }) catch null,
            .zsh => if (t.shell_completions != null and t.shell_completions.?.zsh_cmd != null)
                std.fmt.allocPrint(allocator, "\ncompdef {s}={s}", .{ alias_name, t.id }) catch null
            else
                null,
            else => null,
        };
        if (comp_delegation) |line| {
            defer allocator.free(line);
            section.appendSlice(allocator, line) catch {};
        }
    }

    if (section.items.len == 0) return false;

    shell_mod.ensureSourced(shell_type, allocator) catch {};
    shell_mod.addSection(shell_type, t.id, section.items, allocator) catch {};
    output.printStep("Shell", output.sym_ok, shell_type.name());
    return true;
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

fn printInstallHeader(tool_name: []const u8, version: []const u8, pinned: bool) void {
    const icon = if (pinned) output.sym_pin else output.sym_install;
    std.debug.print("\n{s} {s}Installing{s} {s} {s}\n\n", .{
        icon, output.bold, output.reset, tool_name, version,
    });
}

fn printSuccess(tool: []const u8, duration_s: ?u64) void {
    if (duration_s) |d| {
        std.debug.print("\n{s}{s}{s} {s}{s}{s} installed in {d}s!\n\n", .{
            output.green, output.sym_check, output.reset, output.bold, tool, output.reset, d,
        });
    } else {
        std.debug.print("\n{s}{s}{s} {s}{s}{s} installed!\n\n", .{
            output.green, output.sym_check, output.reset, output.bold, tool, output.reset,
        });
    }
}

fn printPinnedSkip(tool_name: []const u8, tool_id: []const u8, version: []const u8) void {
    std.debug.print("{s}{s}{s} {s}{s}{s} is pinned at {s} — skipping\n", .{ output.cyan, output.sym_pin, output.reset, output.bold, tool_name, output.reset, version });
    std.debug.print("   To upgrade anyway: dot install {s} --force\n", .{tool_id});
}

fn printAlreadyReady(tool: []const u8, version: []const u8) void {
    std.debug.print("\n{s}{s}{s} {s}{s}{s} {s} — already up to date\n\n", .{ output.green, output.sym_check, output.reset, output.bold, tool, output.reset, version });
}

fn printQuickStart(cmds: []const []const u8) void {
    std.debug.print("{s}{s}{s} {s}Quick Start:{s}\n", .{ output.cyan, output.sym_books, output.reset, output.bold, output.reset });
    for (cmds) |cmd| {
        std.debug.print("  $ {s}\n", .{cmd});
    }
    std.debug.print("\n", .{});
}

fn printResources(items: []const []const u8) void {
    std.debug.print("{s}{s}{s} {s}Resources:{s}\n", .{ output.cyan, output.sym_link, output.reset, output.bold, output.reset });
    for (items) |item| {
        std.debug.print("  • {s}\n", .{item});
    }
}

fn printSkipSystem(tool: []const u8, path: []const u8, sys_ver: []const u8, latest: []const u8) void {
    std.debug.print("\n{s}{s}{s}  {s}{s}{s} detected via system package manager\n\n", .{
        output.yellow, output.sym_warn, output.reset, output.bold, tool, output.reset,
    });
    std.debug.print("  Location: {s}\n", .{path});
    std.debug.print("  Version:  {s}\n", .{sys_ver});
    std.debug.print("  Latest:   {s}\n", .{latest});
    std.debug.print("\n  To install dot's version, run: dot install {s} --force\n\n", .{tool});
}

fn printFetchingVersion(name: []const u8) void {
    std.debug.print("{s} Fetching version for {s}...\n", .{ output.sym_search, name });
}

fn printVersionFetchWarning(err_name: []const u8) void {
    std.debug.print("{s}Warning:{s} could not fetch version ({s}), using 'latest'\n", .{ output.yellow, output.reset, err_name });
}

fn printUnknownGroup(name: []const u8) void {
    std.debug.print("{s}Error:{s} unknown group '{s}'\n", .{ output.red, output.reset, name });
    std.debug.print("Available groups: k8s, cloud, iac, containers, utils, terminal, all\n", .{});
}

fn printGroupToolError(id: []const u8, err: anyerror) void {
    std.debug.print("  {s}Failed{s} to install {s}: {s}\n", .{ output.red, output.reset, id, @errorName(err) });
}

fn printGroupBanner(group_name: []const u8, count: usize) void {
    std.debug.print("Installing group '{s}' ({d} tools)...\n", .{ group_name, count });
}

pub fn printGroupToolSeparator(name: []const u8, index: usize, total: usize) void {
    const width = 48;
    const counter_len = blk: {
        // count digits in index and total, plus " [x/y] " = 7 + digits
        var len: usize = 3; // " [" + "]"
        var x = index;
        while (x > 0) : (x /= 10) len += 1;
        var y = total;
        while (y > 0) : (y /= 10) len += 1;
        break :blk len + 1; // +1 for "/"
    };
    const name_len = name.len;
    const dashes_right = if (width > name_len + counter_len + 2)
        width - name_len - counter_len - 2
    else
        0;

    std.debug.print("\n{s}", .{output.dim});
    for (0..2) |_| std.debug.print("{s}", .{output.sym_dash});
    std.debug.print("{s} {s}{s}{s} [{d}/{d}] {s}", .{
        output.reset, output.bold, name, output.reset, index, total, output.dim,
    });
    for (0..dashes_right) |_| std.debug.print("{s}", .{output.sym_dash});
    std.debug.print("{s}\n", .{output.reset});
}

// ─── Fuzzy match ──────────────────────────────────────────────────────────────

/// Single-row Levenshtein distance. Capped at max_len to bound stack use.
fn editDistance(a: []const u8, b: []const u8) usize {
    const max_len = 48;
    var row: [max_len + 1]usize = undefined;
    const la = @min(a.len, max_len);
    const lb = @min(b.len, max_len);
    for (0..lb + 1) |j| row[j] = j;
    for (0..la) |i| {
        var diag = row[0];
        row[0] = i + 1;
        for (0..lb) |j| {
            const above = row[j + 1];
            const cost: usize = if (a[i] == b[j]) 0 else 1;
            row[j + 1] = @min(row[j] + 1, @min(above + 1, diag + cost));
            diag = above;
        }
    }
    return row[lb];
}

/// Return the closest tool id if within edit distance 2, otherwise null.
fn closestTool(id: []const u8, tools: []const tool_mod.Tool) ?[]const u8 {
    var best: ?[]const u8 = null;
    var best_dist: usize = 3; // threshold: suggest only if dist < 3
    for (tools) |t| {
        const distance = editDistance(id, t.id);
        if (distance < best_dist) {
            best_dist = distance;
            best = t.id;
        }
    }
    return best;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

test "parseInstallArgs: tool name only" {
    const args = parseInstallArgs(&.{"helm"});
    try std.testing.expectEqualStrings("helm", args.tool_name);
    try std.testing.expect(args.version_arg == null);
    try std.testing.expect(!args.force);
    try std.testing.expect(!args.group_mode);
}

test "parseInstallArgs: tool name with version" {
    const args = parseInstallArgs(&.{ "helm", "3.15.0" });
    try std.testing.expectEqualStrings("helm", args.tool_name);
    try std.testing.expectEqualStrings("3.15.0", args.version_arg.?);
}

test "parseInstallArgs: --force flag" {
    const args = parseInstallArgs(&.{ "--force", "helm" });
    try std.testing.expect(args.force);
    try std.testing.expectEqualStrings("helm", args.tool_name);
}

test "parseInstallArgs: --force after tool" {
    const args = parseInstallArgs(&.{ "helm", "--force" });
    // --force before tool_name is set is fine; after tool_name is set, --force
    // isn't parsed as a special flag in current logic — it would be version_arg.
    // This test documents current behavior.
    try std.testing.expectEqualStrings("helm", args.tool_name);
}

test "parseInstallArgs: --group flag" {
    const args = parseInstallArgs(&.{ "--group", "k8s" });
    try std.testing.expect(args.group_mode);
    try std.testing.expectEqualStrings("k8s", args.group_name);
    try std.testing.expect(!args.force);
}

test "parseInstallArgs: -g shorthand" {
    const args = parseInstallArgs(&.{ "-g", "iac" });
    try std.testing.expect(args.group_mode);
    try std.testing.expectEqualStrings("iac", args.group_name);
}

test "parseInstallArgs: --force with group" {
    const args = parseInstallArgs(&.{ "--force", "--group", "cloud" });
    try std.testing.expect(args.force);
    try std.testing.expect(args.group_mode);
    try std.testing.expectEqualStrings("cloud", args.group_name);
}

test "parseInstallArgs: empty args" {
    const args = parseInstallArgs(&.{});
    try std.testing.expectEqualStrings("", args.tool_name);
    try std.testing.expect(!args.group_mode);
    try std.testing.expect(!args.force);
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

test "guardedCompletion: fish wraps with if command -q guard" {
    const allocator = std.testing.allocator;
    const result = try guardedCompletion(.fish, "helm", "helm completion fish | source", allocator);
    defer allocator.free(result);
    try std.testing.expect(std.mem.startsWith(u8, result, "if command -q helm\n"));
    try std.testing.expect(std.mem.indexOf(u8, result, "helm completion fish | source") != null);
    try std.testing.expect(std.mem.endsWith(u8, result, "\nend"));
}

test "guardedCompletion: bash wraps with command -v guard" {
    const allocator = std.testing.allocator;
    const result = try guardedCompletion(.bash, "helm", "source <(helm completion bash)", allocator);
    defer allocator.free(result);
    try std.testing.expect(std.mem.startsWith(u8, result, "command -v helm"));
    try std.testing.expect(std.mem.indexOf(u8, result, ">/dev/null 2>&1 &&") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "source <(helm completion bash)") != null);
}

test "guardedCompletion: zsh wraps with command -v guard" {
    const allocator = std.testing.allocator;
    const result = try guardedCompletion(.zsh, "helm", "source <(helm completion zsh)", allocator);
    defer allocator.free(result);
    try std.testing.expect(std.mem.startsWith(u8, result, "command -v helm"));
    try std.testing.expect(std.mem.indexOf(u8, result, ">/dev/null 2>&1 &&") != null);
}

test "guardedCompletion: unknown returns raw cmd" {
    const allocator = std.testing.allocator;
    const result = try guardedCompletion(.unknown, "helm", "helm completion fish | source", allocator);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("helm completion fish | source", result);
}
