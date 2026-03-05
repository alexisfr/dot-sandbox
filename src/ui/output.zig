const std = @import("std");

// ─── ANSI codes — ONLY this file knows about these ───────────────────────────

const CYAN = "\x1b[0;36m";
const GREEN = "\x1b[1;32m";
const RED = "\x1b[1;31m";
const YELLOW = "\x1b[1;33m";
const DIM = "\x1b[2m";
const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";

// ─── Install box ──────────────────────────────────────────────────────────────

fn stepEmoji(step: []const u8) []const u8 {
    if (std.mem.startsWith(u8, step, "Pre-check")) return "🔍";
    if (std.mem.startsWith(u8, step, "Download")) return "📥";
    if (std.mem.startsWith(u8, step, "Verif")) return "🔐";
    if (std.mem.startsWith(u8, step, "Extract")) return "📦";
    if (std.mem.startsWith(u8, step, "Install")) return "🔧";
    if (std.mem.startsWith(u8, step, "Status")) return "📌";
    if (std.mem.startsWith(u8, step, "Shell")) return "🐚";
    if (std.mem.startsWith(u8, step, "Plugin")) return "🔌";
    if (std.mem.startsWith(u8, step, "Config")) return "⚙️ ";
    if (std.mem.startsWith(u8, step, "Link")) return "🔗";
    if (std.mem.startsWith(u8, step, "Valid")) return "✅";
    if (std.mem.startsWith(u8, step, "Cleanup")) return "🧹";
    if (std.mem.startsWith(u8, step, "Brew")) return "🍺";
    return "• ";
}

pub fn printBox(tool: []const u8, version: []const u8) void {
    const inner = 48;
    std.debug.print("{s}+", .{CYAN});
    for (0..inner) |_| std.debug.print("-", .{});
    std.debug.print("+{s}\n", .{RESET});

    const title_len = tool.len + 1 + version.len + " Installation".len + 1;
    const padding = if (inner > title_len + 2) inner - title_len - 2 else 0;
    std.debug.print("{s}|{s} {s}{s}{s} {s} Installation", .{ CYAN, RESET, BOLD, tool, RESET, version });
    for (0..padding) |_| std.debug.print(" ", .{});
    std.debug.print(" {s}|{s}\n", .{ CYAN, RESET });

    std.debug.print("{s}+", .{CYAN});
    for (0..inner) |_| std.debug.print("-", .{});
    std.debug.print("+{s}\n", .{RESET});
}

pub fn printSummary(items: []const []const u8) void {
    std.debug.print("\n{s}📋{s} {s}Summary:{s}\n", .{ CYAN, RESET, BOLD, RESET });
    for (items) |item| {
        std.debug.print("  • {s}\n", .{item});
    }
    std.debug.print("\n", .{});
}

pub fn printStep(step: []const u8, status: []const u8, detail: []const u8) void {
    const emoji = stepEmoji(step);
    const color = if (std.mem.eql(u8, status, "✓"))
        GREEN
    else if (std.mem.eql(u8, status, "→"))
        YELLOW
    else if (std.mem.eql(u8, status, "✗"))
        RED
    else
        DIM;

    std.debug.print("{s} {s}{s:<22}{s} [{s}{s}{s}] {s}\n", .{
        emoji, CYAN, step, RESET, color, status, RESET, detail,
    });
}

pub fn printSuccess(tool: []const u8, duration_s: ?u64) void {
    if (duration_s) |d| {
        std.debug.print("\n{s}✅{s} {s}{s}{s} installed in {d}s!\n\n", .{
            GREEN, RESET, BOLD, tool, RESET, d,
        });
    } else {
        std.debug.print("\n{s}✅{s} {s}{s}{s} installed!\n\n", .{
            GREEN, RESET, BOLD, tool, RESET,
        });
    }
}

pub fn printAlreadyReady(tool: []const u8) void {
    std.debug.print("\n{s}✅{s} {s}{s}{s} ready!\n\n", .{ GREEN, RESET, BOLD, tool, RESET });
}

pub fn printQuickStart(cmds: []const []const u8) void {
    std.debug.print("{s}📚{s} {s}Quick Start:{s}\n", .{ CYAN, RESET, BOLD, RESET });
    for (cmds) |cmd| {
        std.debug.print("  $ {s}\n", .{cmd});
    }
    std.debug.print("\n", .{});
}

pub fn printResources(items: []const []const u8) void {
    std.debug.print("{s}🔗{s} {s}Resources:{s}\n", .{ CYAN, RESET, BOLD, RESET });
    for (items) |item| {
        std.debug.print("  • {s}\n", .{item});
    }
}

pub fn printWarning(msg: []const u8) void {
    std.debug.print("  {s}⚠{s}  {s}\n", .{ YELLOW, RESET, msg });
}

pub fn printError(msg: []const u8) void {
    std.debug.print("\n{s}✗{s} {s}Error:{s} {s}\n\n", .{ RED, RESET, BOLD, RESET, msg });
}

pub fn printSkipSystem(tool: []const u8, path: []const u8, sys_ver: []const u8, latest: []const u8) void {
    std.debug.print("\n{s}⚠{s}  {s}{s}{s} detected via system package manager\n\n", .{
        YELLOW, RESET, BOLD, tool, RESET,
    });
    std.debug.print("  Location: {s}\n", .{path});
    std.debug.print("  Version:  {s}\n", .{sys_ver});
    std.debug.print("  Latest:   {s}\n", .{latest});
    std.debug.print("\n  To install dot's version, run: dot install {s} --force\n\n", .{tool});
}

// ─── Install progress (called from strategy execute() in tool.zig) ────────────

pub fn printDownloading(url: []const u8) void {
    std.debug.print("   Downloading {s}\n", .{url});
}

pub fn printInstalledTo(path: []const u8) void {
    std.debug.print("   Installed to {s}\n", .{path});
}

pub fn printRunningCmd(cmd: []const u8, arg: []const u8) void {
    std.debug.print("   Running: {s} {s}\n", .{ cmd, arg });
}

pub fn printChecksumWarning(err_name: []const u8) void {
    std.debug.print("   {s}Warning:{s} checksum verification failed: {s}\n", .{ YELLOW, RESET, err_name });
}

pub fn printNoPackageManager(pm_name: []const u8) void {
    std.debug.print("   No package found for package manager: {s}\n", .{pm_name});
}

pub fn printHelmPlugin(url: []const u8, ok: bool) void {
    if (ok) {
        std.debug.print("   {s}✓{s} {s}\n", .{ GREEN, RESET, url });
    } else {
        std.debug.print("   {s}-{s} {s} (skipped or already installed)\n", .{ DIM, RESET, url });
    }
}

/// Print an indented detail line (e.g. brew stderr, package manager output).
pub fn printDetail(msg: []const u8) void {
    std.debug.print("   {s}\n", .{msg});
}

// ─── Install command ──────────────────────────────────────────────────────────

pub fn printFetchingVersion(name: []const u8) void {
    std.debug.print("🔍 Fetching latest version for {s}...\n", .{name});
}

pub fn printVersionFetchWarning(err_name: []const u8) void {
    std.debug.print("{s}Warning:{s} could not fetch version ({s}), using 'latest'\n", .{ YELLOW, RESET, err_name });
}

pub fn printInstallUsage() void {
    std.debug.print(
        \\Usage: dot install <tool> [version] [--force]
        \\       dot install --group <group> [--force]
        \\
    , .{});
}

pub fn printUnknownTool(id: []const u8) void {
    std.debug.print("{s}Error:{s} unknown tool '{s}'\n", .{ RED, RESET, id });
    std.debug.print("Run 'dot list' to see available tools\n", .{});
}

pub fn printUnknownGroup(name: []const u8) void {
    std.debug.print("{s}Error:{s} unknown group '{s}'\n", .{ RED, RESET, name });
    std.debug.print("Available groups: k8s, cloud, iac, containers, utils, terminal, all\n", .{});
}

pub fn printNoToolsInGroup(name: []const u8) void {
    std.debug.print("No tools found in group '{s}'\n", .{name});
}

pub fn printGroupInstall(group: []const u8, count: usize) void {
    std.debug.print("Installing group '{s}' ({d} tools)...\n\n", .{ group, count });
}

pub fn printGroupToolError(id: []const u8, err: anyerror) void {
    std.debug.print("  {s}Failed{s} to install {s}: {s}\n", .{ RED, RESET, id, @errorName(err) });
}

// ─── List command ─────────────────────────────────────────────────────────────

pub fn printListHeader() void {
    std.debug.print("\n{s}{s}Available Tools{s}\n\n", .{ CYAN, BOLD, RESET });
    std.debug.print("{s}{s:<16} {s:<33} {s:<14} {s}{s}\n", .{
        BOLD, "Tool", "Description", "Status", "Groups", RESET,
    });
    std.debug.print("{s}", .{DIM});
    for (0..73) |_| std.debug.print("─", .{});
    std.debug.print("{s}\n", .{RESET});
}

pub fn printListRow(id: []const u8, desc: []const u8, installed: bool, groups: []const u8) void {
    const desc_trunc = desc[0..@min(desc.len, 33)];
    std.debug.print("{s:<16} {s:<33} ", .{ id, desc_trunc });
    // Status: hardcoded trailing spaces so visual column width = 14
    // "✓ installed"  = 11 visual chars → +3 spaces
    // "not installed" = 13 visual chars → +1 space
    if (installed) {
        std.debug.print(GREEN ++ "✓ installed" ++ RESET ++ "   ", .{});
    } else {
        std.debug.print(DIM ++ "not installed" ++ RESET ++ " ", .{});
    }
    std.debug.print("{s}\n", .{groups});
}

pub fn printListFooter(count: usize, group_filter: ?[]const u8) void {
    std.debug.print("\n{d} tools total", .{count});
    if (group_filter) |g| std.debug.print(" (filtered by group '{s}')", .{g});
    std.debug.print("\n\n", .{});
}

// ─── Status command ───────────────────────────────────────────────────────────

pub fn printStatusHeader() void {
    std.debug.print("\n{s}{s}Installed Tools{s}\n\n", .{ CYAN, BOLD, RESET });
    std.debug.print("{s}{s:<16} {s:<16} {s:<24} {s}{s}\n", .{
        BOLD, "Tool", "Version", "Installed At", "Method", RESET,
    });
    std.debug.print("{s}", .{DIM});
    for (0..72) |_| std.debug.print("─", .{});
    std.debug.print("{s}\n", .{RESET});
}

pub fn printStatusEmpty() void {
    std.debug.print("  No tools installed yet.\n\n", .{});
    std.debug.print("  Run 'dot install <tool>' to get started.\n\n", .{});
}

pub fn printStatusRow(id: []const u8, version: []const u8, installed_at: []const u8, method: []const u8) void {
    const at_trunc = installed_at[0..@min(installed_at.len, 23)];
    std.debug.print("{s:<16} {s}{s:<16}{s} {s:<24} {s}\n", .{
        id, GREEN, version, RESET, at_trunc, method,
    });
}

pub fn printStatusFooter(count: usize) void {
    std.debug.print("\n{d} tool(s) installed\n\n", .{count});
}

// ─── Doctor command ───────────────────────────────────────────────────────────

pub fn printDoctorHeader() void {
    std.debug.print("\n{s}🔍 Running system checks...{s}\n\n", .{ BOLD, RESET });
}

pub fn printDoctorSection(title: []const u8) void {
    std.debug.print("\n{s}{s}:{s}\n", .{ CYAN, title, RESET });
}

pub fn printCheckPass(label: []const u8, detail: []const u8) void {
    std.debug.print("  {s}✓{s} {s:<24} {s}\n", .{ GREEN, RESET, label, detail });
}

pub fn printCheckWarn(label: []const u8, detail: []const u8) void {
    std.debug.print("  {s}⚠{s}  {s:<24} {s}\n", .{ YELLOW, RESET, label, detail });
}

pub fn printCheckFail(label: []const u8, detail: []const u8) void {
    std.debug.print("  {s}✗{s} {s:<24} {s}\n", .{ RED, RESET, label, detail });
}

pub fn printDoctorSummary(pass: usize, warn: usize, fail: usize) void {
    std.debug.print("\n{s}Summary:{s} {s}{d} passed{s}, {s}{d} warnings{s}, {s}{d} failed{s}\n\n", .{
        BOLD,   RESET,
        GREEN,  pass,  RESET,
        YELLOW, warn,  RESET,
        RED,    fail,  RESET,
    });
}

// ─── Plugin command ───────────────────────────────────────────────────────────

pub fn printPluginListHeader() void {
    std.debug.print("\n{s}{s}Installed Plugins{s}\n\n", .{ CYAN, BOLD, RESET });
}

pub fn printPluginListEnd() void {
    std.debug.print("\n", .{});
}

pub fn printPluginEmpty() void {
    std.debug.print("  No plugins installed.\n\n", .{});
    std.debug.print("  Run 'dot plugin install <url>' to add a plugin.\n\n", .{});
}

pub fn printPluginRow(name: []const u8, version: []const u8, source: []const u8) void {
    std.debug.print("  {s}dot-{s}{s}  {s}  {s}\n", .{ GREEN, name, RESET, version, source });
}

pub fn printPluginInstalling(name: []const u8, source: []const u8) void {
    std.debug.print("🔌 Installing plugin '{s}' from {s}...\n", .{ name, source });
}

pub fn printPluginInstalled(name: []const u8) void {
    std.debug.print("{s}✅{s} Plugin 'dot-{s}' installed\n\n", .{ GREEN, RESET, name });
}

pub fn printPluginRemoved(name: []const u8) void {
    std.debug.print("Removed plugin 'dot-{s}'\n", .{name});
}

pub fn printPluginNotFound(name: []const u8) void {
    std.debug.print("Plugin '{s}' is not installed\n", .{name});
}

pub fn printPluginUpdateFailed(name: []const u8, err: anyerror) void {
    std.debug.print("Failed to update {s}: {s}\n", .{ name, @errorName(err) });
}

pub fn printPluginSourceError(source: []const u8) void {
    std.debug.print("{s}Error:{s} unrecognised source format '{s}'\n", .{ RED, RESET, source });
    std.debug.print("  Expected: https://... URL or local path ./plugin\n", .{});
}

pub fn printPluginGitError() void {
    std.debug.print("  git clone failed\n", .{});
}

pub fn printPluginRepoWarning() void {
    std.debug.print("  {s}Warning:{s} no executable found in repo, copying repo as-is\n", .{ YELLOW, RESET });
}

pub fn printPluginUsage() void {
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

pub fn printPluginInstallUsage() void {
    std.debug.print("Usage: dot plugin install <url|name>\n", .{});
}

pub fn printPluginUninstallUsage() void {
    std.debug.print("Usage: dot plugin uninstall <name>\n", .{});
}

pub fn printUnknownPluginSubcmd(sub: []const u8) void {
    std.debug.print("Unknown plugin subcommand: {s}\n", .{sub});
}

// ─── Upgrade command ──────────────────────────────────────────────────────────

pub fn printUpgradeAll() void {
    std.debug.print("Upgrading all installed tools...\n\n", .{});
}

pub fn printUpgradeFailed(id: []const u8, err: anyerror) void {
    std.debug.print("Failed to upgrade {s}: {s}\n", .{ id, @errorName(err) });
}

// ─── CLI / general ────────────────────────────────────────────────────────────

pub fn printVersion() void {
    std.debug.print("dot version 0.1.0\n", .{});
}

pub fn printHelp() void {
    std.debug.print(
        \\
        \\+--------------------------------------------------+
        \\|  dot — DevOps Toolbox v0.1.0                     |
        \\+--------------------------------------------------+
        \\
        \\Usage: dot <command> [options]
        \\
        \\Commands:
        \\  install <tool> [version]    Install a tool
        \\  install --group <group>     Install all tools in a group
        \\  list [--group <group>]      List available tools
        \\  status                      Show installed tools and versions
        \\  upgrade [tool]              Upgrade one or all tools
        \\  doctor                      Check system health
        \\  plugin <subcommand>         Manage plugins
        \\
        \\Groups:  k8s, cloud, iac, containers, utils, terminal, all
        \\
        \\Plugin subcommands:
        \\  plugin list
        \\  plugin install <url>
        \\  plugin uninstall <name>
        \\  plugin update [name]
        \\
        \\Options:
        \\  --version, -v     Show version
        \\  --help,    -h     Show this help
        \\
        \\
    , .{});
}

pub fn printUnknownCommand(cmd: []const u8) void {
    std.debug.print("Unknown command: {s}\n", .{cmd});
    std.debug.print("Run 'dot --help' for usage.\n", .{});
}

pub fn printUnknownCommandWithSuggestion(cmd: []const u8, suggestion: []const u8) void {
    std.debug.print("Unknown command: {s}\n", .{cmd});
    std.debug.print("Did you mean '{s}'?\n", .{suggestion});
    std.debug.print("Run 'dot --help' for usage.\n", .{});
}
