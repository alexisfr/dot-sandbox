const std = @import("std");
const state_mod = @import("../state.zig");
const tool_mod = @import("../tool.zig");
const platform = @import("../platform.zig");
const output = @import("../ui/output.zig");

const HELP =
    \\Usage: dot doctor
    \\
    \\Run a system health check. Reports:
    \\  • OS and architecture
    \\  • Detected shell and package manager
    \\  • Installed tool binaries and their locations
    \\  • Orphaned state entries (tools no longer in any repository)
    \\  • Shell integration file status
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
    tools: []const tool_mod.Tool,
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

    const home = std.posix.getenv("HOME") orelse "/tmp";

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

    // ~/.local/bin in PATH
    const path_env = std.posix.getenv("PATH") orelse "";
    const local_bin_abs = std.fs.path.join(allocator, &.{ home, ".local", "bin" }) catch null;
    if (local_bin_abs) |lb| {
        defer allocator.free(lb);
        if (std.mem.indexOf(u8, path_env, lb) != null) {
            printCheckPass("~/.local/bin in PATH", "yes"); pass += 1;
        } else {
            printCheckWarn("~/.local/bin in PATH", "not found — tools may not be accessible"); warn += 1;
        }
    }

    // Installed tools: check ~/.local/bin/<id> first, fall back to `which` for
    // system-package installs whose binary lands elsewhere in PATH.
    printDoctorSection("Installed Tools");

    var it = state.tools.iterator();
    while (it.next()) |kv| {
        const id = kv.key_ptr.*;
        const bin_path = std.fs.path.join(allocator, &.{ home, ".local", "bin", id }) catch continue;
        defer allocator.free(bin_path);

        if (std.fs.cwd().access(bin_path, .{})) |_| {
            printCheckPass(id, bin_path); pass += 1;
            continue;
        } else |_| {}

        // Not in ~/.local/bin — try `which` (covers system_package installs)
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "which", id },
            .max_output_bytes = 512,
        }) catch {
            printCheckFail(id, "not found — run: dot install <tool> --force");
            fail += 1;
            continue;
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        if (result.term == .Exited and result.term.Exited == 0) {
            const found_path = std.mem.trimRight(u8, result.stdout, "\n");
            printCheckPass(id, found_path); pass += 1;
        } else {
            printCheckFail(id, "not found — run: dot install <tool> --force"); fail += 1;
        }
    }

    // State consistency: flag entries that are no longer in any repository.
    // "dot" is excluded — it is self-managed via `dot update`.
    printDoctorSection("State Consistency");

    var has_orphan = false;
    var it2 = state.tools.iterator();
    while (it2.next()) |kv| {
        const id = kv.key_ptr.*;
        if (std.mem.eql(u8, id, "dot")) continue;
        var found = false;
        for (tools) |t| {
            if (std.mem.eql(u8, t.id, id)) { found = true; break; }
        }
        if (!found) {
            const detail = std.fmt.allocPrint(allocator, "not in any repository — run: dot uninstall {s}", .{id}) catch null;
            defer if (detail) |d| allocator.free(d);
            printCheckWarn(id, detail orelse "not in any repository");
            warn += 1;
            has_orphan = true;
        }
    }
    if (!has_orphan) {
        printCheckPass("All state entries", "present in repository"); pass += 1;
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

    printDoctorSummary(pass, warn, fail);
}
