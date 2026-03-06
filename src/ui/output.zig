const std = @import("std");

// ─── ANSI codes ───────────────────────────────────────────────────────────────
// Defined here so all styling is configured in one place.
// cmd/ files import these constants rather than hardcoding escape sequences.

pub const CYAN = "\x1b[0;36m";
pub const GREEN = "\x1b[1;32m";
pub const RED = "\x1b[1;31m";
pub const YELLOW = "\x1b[1;33m";
pub const DIM = "\x1b[2m";
pub const BOLD = "\x1b[1m";
pub const RESET = "\x1b[0m";

// ─── Symbols / Emoji ─────────────────────────────────────────────────────────
// Defined here so they can be swapped for ASCII equivalents on terminals that
// do not support Unicode or emoji (e.g. NO_COLOR, Windows cmd, CI logs).

pub const SYM_OK = "✓";
pub const SYM_FAIL = "✗";
pub const SYM_WARN = "⚠";
pub const SYM_CHECK = "✅";
pub const SYM_PIN = "📌";
pub const SYM_LIST = "📋";
pub const SYM_BOOKS = "📚";
pub const SYM_LINK = "🔗";
pub const SYM_SEARCH = "🔍";
pub const SYM_PLUG = "🔌";
pub const SYM_DASH = "─";

// ─── Common print functions ───────────────────────────────────────────────────

/// Print plain text as-is. Used for HELP strings and similar.
pub fn printRaw(text: []const u8) void {
    std.debug.print("{s}", .{text});
}

/// Generic formatted print for one-off messages in cmd/ files.
pub fn printFmt(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}

pub fn printWarning(msg: []const u8) void {
    std.debug.print("  {s}{s}{s}  {s}\n", .{ YELLOW, SYM_WARN, RESET, msg });
}

pub fn printError(msg: []const u8) void {
    std.debug.print("\n{s}{s}{s} {s}Error:{s} {s}\n\n", .{ RED, SYM_FAIL, RESET, BOLD, RESET, msg });
}

/// Used by both install and upgrade commands.
pub fn printUnknownTool(id: []const u8) void {
    std.debug.print("{s}Error:{s} unknown tool '{s}'\n", .{ RED, RESET, id });
    std.debug.print("Run 'dot list' to see available tools\n", .{});
}

// ─── Step progress (shared by install and uninstall commands) ─────────────────

fn stepEmoji(step: []const u8) []const u8 {
    if (std.mem.startsWith(u8, step, "Pre-check")) return SYM_SEARCH;
    if (std.mem.startsWith(u8, step, "Download")) return "📥";
    if (std.mem.startsWith(u8, step, "Verif")) return "🔐";
    if (std.mem.startsWith(u8, step, "Extract")) return "📦";
    if (std.mem.startsWith(u8, step, "Install")) return "🔧";
    if (std.mem.startsWith(u8, step, "Status")) return SYM_PIN;
    if (std.mem.startsWith(u8, step, "Shell")) return "🐚";
    if (std.mem.startsWith(u8, step, "Plugin")) return SYM_PLUG;
    if (std.mem.startsWith(u8, step, "Config")) return "⚙️ ";
    if (std.mem.startsWith(u8, step, "Link")) return SYM_LINK;
    if (std.mem.startsWith(u8, step, "Valid")) return SYM_CHECK;
    if (std.mem.startsWith(u8, step, "Cleanup")) return "🧹";
    if (std.mem.startsWith(u8, step, "Brew")) return "🍺";
    return "• ";
}

pub fn printStep(step: []const u8, status: []const u8, detail: []const u8) void {
    const emoji = stepEmoji(step);
    const color = if (std.mem.eql(u8, status, SYM_OK))
        GREEN
    else if (std.mem.eql(u8, status, "→"))
        YELLOW
    else if (std.mem.eql(u8, status, SYM_FAIL))
        RED
    else
        DIM;

    std.debug.print("{s} {s}{s:<22}{s} [{s}{s}{s}] {s}\n", .{
        emoji, CYAN, step, RESET, color, status, RESET, detail,
    });
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

pub fn printDetail(msg: []const u8) void {
    std.debug.print("   {s}\n", .{msg});
}
