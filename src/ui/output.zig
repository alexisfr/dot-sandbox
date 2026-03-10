const std = @import("std");

// ─── Render mode ──────────────────────────────────────────────────────────────

pub const RenderMode = enum {
    rich,
    plain,
    pipe,
    /// Used in tests to suppress all output while still exercising logic.
    silent,
};

var render_mode: RenderMode = .rich;

/// Detect terminal capabilities. Call once at program startup before any output.
pub fn initCaps() void {
    const no_color = std.posix.getenv("NO_COLOR") != null;
    const dumb_term = if (std.posix.getenv("TERM")) |t| std.mem.eql(u8, t, "dumb") else false;
    const is_tty = std.posix.isatty(2); // fd 2 = stderr

    render_mode = if (!is_tty) .pipe else if (no_color or dumb_term) .plain else .rich;

    if (render_mode != .rich) {
        CYAN = "";
        GREEN = "";
        RED = "";
        YELLOW = "";
        DIM = "";
        BOLD = "";
        RESET = "";
        SYM_OK = "ok";
        SYM_FAIL = "FAIL";
        SYM_WARN = "WARN";
        SYM_CHECK = "[OK]";
        SYM_PIN = "[PIN]";
        SYM_LIST = "[INFO]";
        SYM_BOOKS = "[DOC]";
        SYM_LINK = "[LK]";
        SYM_SEARCH = "[..]";
        SYM_DASH = "-";
        SYM_ARROW = "->";
        SYM_INSTALL = "[IN]";
    }
}

pub fn getRenderMode() RenderMode {
    return render_mode;
}

/// For tests only: override render mode without reading environment/TTY.
pub fn setRenderModeForTesting(mode: RenderMode) void {
    render_mode = mode;
}

// ─── ANSI codes ───────────────────────────────────────────────────────────────
// Defined here so all styling is configured in one place.
// cmd/ files import these variables rather than hardcoding escape sequences.
// In plain/pipe mode, initCaps() sets these to empty strings.

pub var CYAN: []const u8 = "\x1b[0;36m";
pub var GREEN: []const u8 = "\x1b[1;32m";
pub var RED: []const u8 = "\x1b[1;31m";
pub var YELLOW: []const u8 = "\x1b[1;33m";
pub var DIM: []const u8 = "\x1b[2m";
pub var BOLD: []const u8 = "\x1b[1m";
pub var RESET: []const u8 = "\x1b[0m";

// ─── Symbols / Emoji ─────────────────────────────────────────────────────────
// initCaps() replaces these with ASCII equivalents in plain/pipe mode.

pub var SYM_OK: []const u8 = "✓";
pub var SYM_FAIL: []const u8 = "✗";
pub var SYM_WARN: []const u8 = "⚠";
pub var SYM_CHECK: []const u8 = "✅";
pub var SYM_PIN: []const u8 = "📌";
pub var SYM_LIST: []const u8 = "📋";
pub var SYM_BOOKS: []const u8 = "📚";
pub var SYM_LINK: []const u8 = "🔗";
pub var SYM_SEARCH: []const u8 = "🔍";
pub var SYM_DASH: []const u8 = "─";
/// Progress/in-flight indicator: "→" in rich mode, "->" in plain/pipe.
pub var SYM_ARROW: []const u8 = "→";
/// Install action indicator: "🔧" in rich mode, "[IN]" in plain/pipe.
pub var SYM_INSTALL: []const u8 = "🔧";

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

/// Pure mapping from step name to its icon/prefix for a given render mode.
/// Exported so tests can verify the mapping without depending on global state.
pub fn stepPrefixForMode(step: []const u8, mode: RenderMode) []const u8 {
    if (mode == .rich) {
        if (std.mem.startsWith(u8, step, "Pre-check")) return "🔍";
        if (std.mem.startsWith(u8, step, "Download")) return "📥";
        if (std.mem.startsWith(u8, step, "Verif")) return "🔐";
        if (std.mem.startsWith(u8, step, "Extract")) return "📦";
        if (std.mem.startsWith(u8, step, "Install")) return "🔧";
        if (std.mem.startsWith(u8, step, "Status")) return "📌";
        if (std.mem.startsWith(u8, step, "Shell")) return "🐚";
        if (std.mem.startsWith(u8, step, "Config")) return "⚙️ ";
        if (std.mem.startsWith(u8, step, "Link")) return "🔗";
        if (std.mem.startsWith(u8, step, "Valid")) return "✅";
        if (std.mem.startsWith(u8, step, "Cleanup")) return "🧹";
        if (std.mem.startsWith(u8, step, "Brew")) return "🍺";
        if (std.mem.startsWith(u8, step, "Post-")) return "🔄";
        return "• ";
    } else {
        if (std.mem.startsWith(u8, step, "Pre-check")) return "[..]";
        if (std.mem.startsWith(u8, step, "Download")) return "[DL]";
        if (std.mem.startsWith(u8, step, "Verif")) return "[VF]";
        if (std.mem.startsWith(u8, step, "Extract")) return "[EX]";
        if (std.mem.startsWith(u8, step, "Install")) return "[IN]";
        if (std.mem.startsWith(u8, step, "Status")) return "[PI]";
        if (std.mem.startsWith(u8, step, "Shell")) return "[SH]";
        if (std.mem.startsWith(u8, step, "Config")) return "[CF]";
        if (std.mem.startsWith(u8, step, "Link")) return "[LK]";
        if (std.mem.startsWith(u8, step, "Valid")) return "[OK]";
        if (std.mem.startsWith(u8, step, "Cleanup")) return "[CL]";
        if (std.mem.startsWith(u8, step, "Brew")) return "[BR]";
        if (std.mem.startsWith(u8, step, "Post-")) return "[PO]";
        return "[--]";
    }
}

fn stepPrefix(step: []const u8) []const u8 {
    return stepPrefixForMode(step, render_mode);
}

pub fn printStep(step: []const u8, status: []const u8, detail: []const u8) void {
    if (render_mode == .silent) return;
    const prefix = stepPrefix(step);
    const color = if (std.mem.eql(u8, status, SYM_OK))
        GREEN
    else if (std.mem.eql(u8, status, SYM_ARROW))
        YELLOW
    else if (std.mem.eql(u8, status, SYM_FAIL))
        RED
    else
        DIM;

    if (detail.len > 0) {
        std.debug.print("{s} {s}{s:<14}{s}  {s}{s}{s}  {s}\n", .{
            prefix, BOLD, step, RESET, color, status, RESET, detail,
        });
    } else {
        std.debug.print("{s} {s}{s:<14}{s}  {s}{s}{s}\n", .{
            prefix, BOLD, step, RESET, color, status, RESET,
        });
    }
}

/// Print an in-progress step indicator that stays on the current line (no newline).
/// Follow with printStepDone() to overwrite it with the completed state.
/// In pipe/silent mode: no-op — printStepDone() will print the single final line.
pub fn printStepStart(step: []const u8, detail: []const u8) void {
    if (render_mode == .silent or render_mode == .pipe) return;
    const prefix = stepPrefix(step);
    std.debug.print("{s} {s}{s:<14}{s}  {s}…{s}  {s}", .{
        prefix, BOLD, step, RESET, DIM, RESET, detail,
    }); // intentionally no \n — cursor stays on this line
}

/// Complete a step started with printStepStart(), overwriting the in-progress line.
/// In pipe mode: prints the step as a normal completed line (no in-progress line was shown).
pub fn printStepDone(step: []const u8, detail: []const u8) void {
    if (render_mode == .silent) return;
    switch (render_mode) {
        .rich => std.debug.print("\r\x1b[2K", .{}),
        .plain => std.debug.print("\r{s:<80}\r", .{""}),
        .pipe, .silent => {},
    }
    printStep(step, SYM_OK, detail);
}

// ─── Install progress (called from strategy execute() in tool.zig) ────────────

/// No-op: the ProgressBar handles all downloading feedback in every mode.
/// bar.finish() in pipe mode prints the single completion line.
pub fn printDownloading(url: []const u8) void {
    _ = url;
}

/// No-op: install.zig's printStep("Installation", ...) shows the path instead.
pub fn printInstalledTo(path: []const u8) void {
    _ = path;
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

// ─── Tests ────────────────────────────────────────────────────────────────────

test "stepPrefixForMode: rich mode step names" {
    try std.testing.expectEqualStrings("🔍", stepPrefixForMode("Pre-checks", .rich));
    try std.testing.expectEqualStrings("📥", stepPrefixForMode("Downloading", .rich));
    try std.testing.expectEqualStrings("🔐", stepPrefixForMode("Verifying", .rich));
    try std.testing.expectEqualStrings("📦", stepPrefixForMode("Extracting", .rich));
    try std.testing.expectEqualStrings("🔧", stepPrefixForMode("Installation", .rich));
    try std.testing.expectEqualStrings("📌", stepPrefixForMode("Status", .rich));
    try std.testing.expectEqualStrings("🐚", stepPrefixForMode("Shell integration", .rich));
    try std.testing.expectEqualStrings("⚙️ ", stepPrefixForMode("Config", .rich));
    try std.testing.expectEqualStrings("🔗", stepPrefixForMode("Link", .rich));
    try std.testing.expectEqualStrings("✅", stepPrefixForMode("Validation", .rich));
    try std.testing.expectEqualStrings("🧹", stepPrefixForMode("Cleanup", .rich));
    try std.testing.expectEqualStrings("🍺", stepPrefixForMode("Brew", .rich));
    try std.testing.expectEqualStrings("🔄", stepPrefixForMode("Post-install", .rich));
    try std.testing.expectEqualStrings("• ", stepPrefixForMode("Unknown step", .rich));
}

test "stepPrefixForMode: plain mode step names" {
    try std.testing.expectEqualStrings("[..]", stepPrefixForMode("Pre-checks", .plain));
    try std.testing.expectEqualStrings("[DL]", stepPrefixForMode("Downloading", .plain));
    try std.testing.expectEqualStrings("[VF]", stepPrefixForMode("Verifying", .plain));
    try std.testing.expectEqualStrings("[EX]", stepPrefixForMode("Extracting", .plain));
    try std.testing.expectEqualStrings("[IN]", stepPrefixForMode("Installation", .plain));
    try std.testing.expectEqualStrings("[PI]", stepPrefixForMode("Status", .plain));
    try std.testing.expectEqualStrings("[SH]", stepPrefixForMode("Shell integration", .plain));
    try std.testing.expectEqualStrings("[CF]", stepPrefixForMode("Config", .plain));
    try std.testing.expectEqualStrings("[LK]", stepPrefixForMode("Link", .plain));
    try std.testing.expectEqualStrings("[OK]", stepPrefixForMode("Validation", .plain));
    try std.testing.expectEqualStrings("[CL]", stepPrefixForMode("Cleanup", .plain));
    try std.testing.expectEqualStrings("[BR]", stepPrefixForMode("Brew", .plain));
    try std.testing.expectEqualStrings("[PO]", stepPrefixForMode("Post-install", .plain));
    try std.testing.expectEqualStrings("[--]", stepPrefixForMode("Unknown step", .plain));
}

test "stepPrefixForMode: pipe mode uses same prefixes as plain" {
    // Pipe mode has no TTY so must not emit emoji
    try std.testing.expectEqualStrings("[DL]", stepPrefixForMode("Downloading", .pipe));
    try std.testing.expectEqualStrings("[IN]", stepPrefixForMode("Installation", .pipe));
    try std.testing.expectEqualStrings("[--]", stepPrefixForMode("Unknown", .pipe));
}

test "stepPrefixForMode: prefix matching is prefix not exact" {
    // Verifies we match on startsWith, not equality
    try std.testing.expectEqualStrings("📥", stepPrefixForMode("Downloading helm", .rich));
    try std.testing.expectEqualStrings("[DL]", stepPrefixForMode("Downloading helm", .plain));
    try std.testing.expectEqualStrings("🔧", stepPrefixForMode("Installation complete", .rich));
}
