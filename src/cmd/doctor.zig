const std = @import("std");
const state_mod = @import("../state.zig");
const platform = @import("../platform.zig");
const output = @import("../ui/output.zig");

const HELP =
    \\Usage: dot doctor
    \\
    \\Run a system health check. Reports:
    \\  • OS and architecture
    \\  • Detected shell and package manager
    \\  • Installed tool binaries and their locations
    \\  • Shell integration file status
    \\  • Plugin directory status
    \\
    \\Options:
    \\  --help, -h    Show this help
    \\
;

// ─── Doctor-specific print functions ──────────────────────────────────────────

fn printDoctorHeader() void {
    std.debug.print("\n{s}{s} Running system checks...{s}\n\n", .{ output.BOLD, output.SYM_SEARCH, output.RESET });
}

fn printDoctorSection(title: []const u8) void {
    std.debug.print("\n{s}{s}:{s}\n", .{ output.CYAN, title, output.RESET });
}

fn printCheckPass(label: []const u8, detail: []const u8) void {
    std.debug.print("  {s}{s}{s} {s:<24} {s}\n", .{ output.GREEN, output.SYM_OK, output.RESET, label, detail });
}

fn printCheckWarn(label: []const u8, detail: []const u8) void {
    std.debug.print("  {s}{s}{s}  {s:<24} {s}\n", .{ output.YELLOW, output.SYM_WARN, output.RESET, label, detail });
}

fn printCheckFail(label: []const u8, detail: []const u8) void {
    std.debug.print("  {s}{s}{s} {s:<24} {s}\n", .{ output.RED, output.SYM_FAIL, output.RESET, label, detail });
}

fn printDoctorSummary(pass: usize, warn: usize, fail: usize) void {
    std.debug.print("\n{s}Summary:{s} {s}{d} passed{s}, {s}{d} warnings{s}, {s}{d} failed{s}\n\n", .{
        output.BOLD,   output.RESET,
        output.GREEN,  pass,  output.RESET,
        output.YELLOW, warn,  output.RESET,
        output.RED,    fail,  output.RESET,
    });
}

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
) !void {
    for (args) |a| {
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            output.printRaw(HELP);
            return;
        }
    }

    printDoctorHeader();

    var pass: usize = 0;
    var warn: usize = 0;
    var fail: usize = 0;

    // Platform
    const os = platform.Os.current();
    const arch = platform.Arch.current();
    printCheckPass("OS", os.name()); pass += 1;
    printCheckPass("Arch", arch.goName()); pass += 1;

    // Shell
    const sh = platform.Shell.detect();
    printCheckPass("Shell", sh.name()); pass += 1;

    // Package manager
    const pm = platform.PackageManager.detect();
    if (pm != .unknown) {
        printCheckPass("Package Manager", pm.command() orelse "unknown"); pass += 1;
    } else {
        printCheckWarn("Package Manager", "none detected"); warn += 1;
    }

    // Installed tools: verify binaries exist in ~/.local/bin
    printDoctorSection("Installed Tools");

    const home = std.posix.getenv("HOME") orelse "/tmp";
    var it = state.tools.iterator();
    while (it.next()) |kv| {
        const id = kv.key_ptr.*;
        const bin_path = std.fs.path.join(allocator, &.{ home, ".local", "bin", id }) catch continue;
        defer allocator.free(bin_path);

        if (std.fs.cwd().access(bin_path, .{})) |_| {
            printCheckPass(id, bin_path); pass += 1;
        } else |_| {
            printCheckFail(id, "binary missing from ~/.local/bin"); fail += 1;
        }
    }

    // Shell integration file
    printDoctorSection("Shell Integration");

    const integ_path = std.fs.path.join(allocator, &.{
        home, ".local", "bin", sh.integrationFileName(),
    }) catch null;
    if (integ_path) |p| {
        defer allocator.free(p);
        if (std.fs.cwd().access(p, .{})) |_| {
            printCheckPass("Integration file", p); pass += 1;
        } else |_| {
            printCheckWarn("Integration file", "not found (run a tool install to create it)"); warn += 1;
        }
    }

    // Plugin directory
    const plugin_dir = std.fs.path.join(allocator, &.{
        home, ".local", "share", "dot", "plugins",
    }) catch null;
    if (plugin_dir) |p| {
        defer allocator.free(p);
        if (std.fs.cwd().access(p, .{})) |_| {
            printCheckPass("Plugin dir", p); pass += 1;
        } else |_| {
            printCheckWarn("Plugin dir", "not found (created on first plugin install)"); warn += 1;
        }
    }

    printDoctorSummary(pass, warn, fail);
}
