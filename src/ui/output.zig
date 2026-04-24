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
        cyan = "";
        green = "";
        red = "";
        yellow = "";
        dim = "";
        bold = "";
        reset = "";
        sym_ok = "ok";
        sym_ok_w = 2;
        sym_fail = "FAIL";
        sym_warn = "WARN";
        sym_warn_w = 4;
        sym_check = "[OK]";
        sym_pin = "[PIN]";
        sym_list = "[INFO]";
        sym_books = "[DOC]";
        sym_link = "[LK]";
        sym_search = "[..]";
        sym_dash = "-";
        sym_arrow = "->";
        sym_install = "[IN]";
        spin_frames = &.{ "|", "/", "-", "\\" };
        spin_frame_w = 1;
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

pub var cyan: []const u8 = "\x1b[1;34m";
pub var green: []const u8 = "\x1b[1;32m";
pub var red: []const u8 = "\x1b[1;31m";
pub var yellow: []const u8 = "\x1b[1;33m";
pub var dim: []const u8 = "\x1b[2m";
pub var bold: []const u8 = "\x1b[1m";
pub var reset: []const u8 = "\x1b[0m";

// ─── Symbols / Emoji ─────────────────────────────────────────────────────────
// initCaps() replaces these with ASCII equivalents in plain/pipe mode.

pub var sym_ok: []const u8 = "✓";
pub var sym_fail: []const u8 = "✗";
pub var sym_warn: []const u8 = "⚠";
pub var sym_check: []const u8 = "✅";
pub var sym_pin: []const u8 = "📌";
pub var sym_list: []const u8 = "📋";
pub var sym_books: []const u8 = "📚";
pub var sym_link: []const u8 = "🔗";
pub var sym_search: []const u8 = "🔍";
pub var sym_dash: []const u8 = "─";
/// Progress/in-flight indicator: "→" in rich mode, "->" in plain/pipe.
pub var sym_arrow: []const u8 = "→";
/// Install action indicator: "🔧" in rich mode, "[IN]" in plain/pipe.
pub var sym_install: []const u8 = "🔧";
/// Visual width of sym_ok (1 in rich mode, 2 in plain/pipe for "ok").
pub var sym_ok_w: usize = 1;
/// Visual width of sym_warn (1 in rich mode, 4 in plain/pipe for "WARN").
pub var sym_warn_w: usize = 1;

// ─── Spinner frames ───────────────────────────────────────────────────────────
// Two paired frame sets: rich (braille) ↔ plain (slash). Both width-1 so
// redraws never need to compensate for a changing cell count.
// initCaps() swaps to the plain set when render_mode != .rich.

pub var spin_frames: []const []const u8 = &.{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧" };
pub var spin_frame_w: usize = 1; // visual column width of each frame glyph

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
    std.debug.print("  {s}{s}{s}  {s}\n", .{ yellow, sym_warn, reset, msg });
}

pub fn printError(msg: []const u8) void {
    std.debug.print("\n{s}{s}{s} {s}Error:{s} {s}\n\n", .{ red, sym_fail, reset, bold, reset, msg });
}

/// Used by both install and upgrade commands.
pub fn printUnknownTool(id: []const u8) void {
    std.debug.print("{s}Error:{s} unknown tool '{s}'\n", .{ red, reset, id });
    std.debug.print("Run 'dot list' to see available tools\n", .{});
}

// ─── Step lines — brew style ─────────────────────────────────────────────────
// Every step is a "==> Step  detail" line. No emoji prefixes, no status symbols
// on success. Failures get a red prefix. The download spinner is a separate
// indented line managed by progress.zig — not a step line.

pub fn printStep(step: []const u8, status: []const u8, detail: []const u8) void {
    if (render_mode == .silent) return;
    const is_fail = std.mem.eql(u8, status, sym_fail);
    if (is_fail) {
        if (detail.len > 0) {
            std.debug.print("{s}==>{s} {s}Error:{s} {s} {s}\n", .{ red, reset, bold, reset, step, detail });
        } else {
            std.debug.print("{s}==>{s} {s}Error:{s} {s}\n", .{ red, reset, bold, reset, step });
        }
    } else {
        if (detail.len > 0) {
            std.debug.print("{s}==>{s} {s}{s}{s} {s}\n", .{ cyan, reset, bold, step, reset, detail });
        } else {
            std.debug.print("{s}==>{s} {s}{s}{s}\n", .{ cyan, reset, bold, step, reset });
        }
    }
}

/// Same as printStep — in brew style there is no "in-progress" state for
/// non-download steps; we just print the header immediately.
pub fn printStepStart(step: []const u8, detail: []const u8) void {
    printStep(step, sym_ok, detail);
}

/// In brew style, printStepStart already printed the header; this is a no-op.
/// Kept for call-site compatibility.
pub fn printStepDone(step: []const u8, detail: []const u8) void {
    _ = step;
    _ = detail;
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
    std.debug.print("   {s}Warning:{s} checksum verification failed: {s}\n", .{ yellow, reset, err_name });
}

pub fn printNoPackageManager(pm_name: []const u8) void {
    std.debug.print("   No package found for package manager: {s}\n", .{pm_name});
}

pub fn printDetail(msg: []const u8) void {
    std.debug.print("   {s}\n", .{msg});
}

/// Brew-style section header: "==> <title>" in bold. Used by all commands.
pub fn printSectionHeader(title: []const u8) void {
    if (render_mode == .silent) return;
    std.debug.print("\n{s}==>{s} {s}{s}{s}\n", .{ cyan, reset, bold, title, reset });
}

pub fn printSectionHeaderFmt(comptime fmt: []const u8, args: anytype) void {
    if (render_mode == .silent) return;
    std.debug.print("\n{s}==>{s} {s}", .{ cyan, reset, bold });
    std.debug.print(fmt, args);
    std.debug.print("{s}\n", .{reset});
}

/// Print a "==> Caveats" block with indented lines. Pass a slice of message strings.
pub fn printCaveats(lines: []const []const u8) void {
    if (render_mode == .silent or lines.len == 0) return;
    printSectionHeader("Caveats");
    for (lines) |line| {
        std.debug.print("  {s}\n", .{line});
    }
}

/// Print the upgrade/install summary line: "==> Summary: X upgraded · Y current · Z failed · Ns"
pub fn printSummary(upgraded: usize, uptodate: usize, failed: usize, elapsed_ms: u64) void {
    if (render_mode == .silent) return;
    const secs = elapsed_ms / 1000;
    const frac = (elapsed_ms % 1000) / 100;
    printSectionHeader("Summary");
    std.debug.print("  {s}{d} upgraded{s}  ·  {d} already current  ·  ", .{
        green, upgraded, reset, uptodate,
    });
    if (failed > 0) {
        std.debug.print("{s}{d} failed{s}", .{ red, failed, reset });
    } else {
        std.debug.print("{s}{d} failed{s}", .{ dim, failed, reset });
    }
    std.debug.print("  ·  {d}.{d}s\n", .{ secs, frac });
}

// ─── Tests ────────────────────────────────────────────────────────────────────
