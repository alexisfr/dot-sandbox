const std = @import("std");

// ANSI color codes
const CYAN = "\x1b[0;36m";
const GREEN = "\x1b[1;32m";
const RED = "\x1b[1;31m";
const YELLOW = "\x1b[1;33m";
const DIM = "\x1b[2m";
const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";

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

/// Print the installation header box.
/// +------------------------------------------------+
/// | Helm v3.15.0 Installation                      |
/// +------------------------------------------------+
pub fn printBox(tool: []const u8, version: []const u8) void {
    const inner = 48;
    std.debug.print("{s}+", .{CYAN});
    var i: usize = 0;
    while (i < inner) : (i += 1) std.debug.print("-", .{});
    std.debug.print("+{s}\n", .{RESET});

    // Title line
    const title_len = tool.len + 1 + version.len + " Installation".len + 1;
    const padding = if (inner > title_len + 2) inner - title_len - 2 else 0;
    std.debug.print("{s}|{s} {s}{s}{s} {s} Installation", .{ CYAN, RESET, BOLD, tool, RESET, version });
    i = 0;
    while (i < padding) : (i += 1) std.debug.print(" ", .{});
    std.debug.print(" {s}|{s}\n", .{ CYAN, RESET });

    std.debug.print("{s}+", .{CYAN});
    i = 0;
    while (i < inner) : (i += 1) std.debug.print("-", .{});
    std.debug.print("+{s}\n", .{RESET});
}

/// Print a summary section with bullet items.
pub fn printSummary(items: []const []const u8) void {
    std.debug.print("\n{s}📋{s} {s}Summary:{s}\n", .{ CYAN, RESET, BOLD, RESET });
    for (items) |item| {
        std.debug.print("  • {s}\n", .{item});
    }
}

/// Print a step status line.
/// Statuses: "✓" (success), "→" (in progress), "✗" (failed), "-" (skipped)
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
        emoji,
        CYAN,
        step,
        RESET,
        color,
        status,
        RESET,
        detail,
    });
}

/// Print success completion message.
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

/// Print "already up to date" message.
pub fn printAlreadyReady(tool: []const u8) void {
    std.debug.print("\n{s}✅{s} {s}{s}{s} ready!\n\n", .{ GREEN, RESET, BOLD, tool, RESET });
}

/// Print quick-start command examples.
pub fn printQuickStart(cmds: []const []const u8) void {
    std.debug.print("{s}📚{s} {s}Quick Start:{s}\n", .{ CYAN, RESET, BOLD, RESET });
    for (cmds) |cmd| {
        std.debug.print("  $ {s}\n", .{cmd});
    }
    std.debug.print("\n", .{});
}

/// Print resource links.
pub fn printResources(items: []const []const u8) void {
    std.debug.print("{s}🔗{s} {s}Resources:{s}\n", .{ CYAN, RESET, BOLD, RESET });
    for (items) |item| {
        std.debug.print("  • {s}\n", .{item});
    }
}

/// Print a warning (non-fatal).
pub fn printWarning(msg: []const u8) void {
    std.debug.print("  {s}⚠{s}  {s}\n", .{ YELLOW, RESET, msg });
}

/// Print an error message.
pub fn printError(msg: []const u8) void {
    std.debug.print("\n{s}✗{s} {s}Error:{s} {s}\n\n", .{ RED, RESET, BOLD, RESET, msg });
}

/// Print a skip message for system-managed tool.
pub fn printSkipSystem(tool: []const u8, path: []const u8, sys_ver: []const u8, latest: []const u8) void {
    std.debug.print("\n{s}⚠{s}  {s}{s}{s} detected via system package manager\n\n", .{
        YELLOW, RESET, BOLD, tool, RESET,
    });
    std.debug.print("  Location: {s}\n", .{path});
    std.debug.print("  Version:  {s}\n", .{sys_ver});
    std.debug.print("  Latest:   {s}\n", .{latest});
    std.debug.print("\n  To install dot's version, run: dot install {s} --force\n\n", .{tool});
}
