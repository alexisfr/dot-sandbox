const std = @import("std");
const state_mod = @import("../state.zig");
const registry = @import("../registry/mod.zig");
const platform = @import("../platform.zig");

const GREEN = "\x1b[1;32m";
const RED = "\x1b[1;31m";
const YELLOW = "\x1b[1;33m";
const CYAN = "\x1b[0;36m";
const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
) !void {
    _ = args;

    std.debug.print("\n{s}🔍 Running system checks...{s}\n\n", .{ BOLD, RESET });

    var pass: usize = 0;
    var warn: usize = 0;
    var fail: usize = 0;

    // Platform
    const os = platform.Os.current();
    const arch = platform.Arch.current();
    checkOk("OS", os.name(), &pass);
    checkOk("Arch", arch.goName(), &pass);

    // Shell
    const sh = platform.Shell.detect();
    checkOk("Shell", sh.name(), &pass);

    // Package manager
    const pm = platform.PackageManager.detect();
    if (pm != .unknown) {
        checkOk("Package Manager", pm.command() orelse "unknown", &pass);
    } else {
        checkWarn("Package Manager", "none detected", &warn);
    }

    // Installed tools: verify binaries exist in ~/.local/bin
    std.debug.print("\n{s}Installed Tools:{s}\n", .{ CYAN, RESET });

    const home = std.posix.getenv("HOME") orelse "/tmp";
    var it = state.tools.iterator();
    while (it.next()) |kv| {
        const id = kv.key_ptr.*;
        const bin_path = std.fs.path.join(allocator, &.{ home, ".local", "bin", id }) catch continue;
        defer allocator.free(bin_path);

        std.fs.cwd().access(bin_path, .{}) catch {
            checkFail(id, "binary missing from ~/.local/bin", &fail);
            continue;
        };
        checkOk(id, bin_path, &pass);
    }

    // Shell integration file
    std.debug.print("\n{s}Shell Integration:{s}\n", .{ CYAN, RESET });
    const integ_path = std.fs.path.join(allocator, &.{
        home, ".local", "bin", sh.integrationFileName(),
    }) catch null;
    if (integ_path) |p| {
        defer allocator.free(p);
        if (std.fs.cwd().access(p, .{})) |_| {
            checkOk("Integration file", p, &pass);
        } else |_| {
            checkWarn("Integration file", "not found (run a tool install to create it)", &warn);
        }
    }

    // Plugin directory
    const plugin_dir = std.fs.path.join(allocator, &.{
        home, ".local", "share", "dot", "plugins",
    }) catch null;
    if (plugin_dir) |p| {
        defer allocator.free(p);
        if (std.fs.cwd().access(p, .{})) |_| {
            checkOk("Plugin dir", p, &pass);
        } else |_| {
            checkWarn("Plugin dir", "not found (created on first plugin install)", &warn);
        }
    }

    summarize(pass, warn, fail);
}

fn checkOk(label: []const u8, detail: []const u8, pass: *usize) void {
    std.debug.print("  {s}✓{s} {s:<24} {s}\n", .{ GREEN, RESET, label, detail });
    pass.* += 1;
}

fn checkWarn(label: []const u8, detail: []const u8, warn: *usize) void {
    std.debug.print("  {s}⚠{s}  {s:<24} {s}\n", .{ YELLOW, RESET, label, detail });
    warn.* += 1;
}

fn checkFail(label: []const u8, detail: []const u8, fail: *usize) void {
    std.debug.print("  {s}✗{s} {s:<24} {s}\n", .{ RED, RESET, label, detail });
    fail.* += 1;
}

fn summarize(pass: usize, warn: usize, fail: usize) void {
    std.debug.print("\n{s}Summary:{s} {s}{d} passed{s}, {s}{d} warnings{s}, {s}{d} failed{s}\n\n", .{
        BOLD,   RESET,
        GREEN,  pass, RESET,
        YELLOW, warn, RESET,
        RED,    fail, RESET,
    });
}
