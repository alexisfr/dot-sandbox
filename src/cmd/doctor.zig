const std = @import("std");
const state_mod = @import("../state.zig");
const platform = @import("../platform.zig");
const output = @import("../ui/output.zig");

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
) !void {
    _ = args;

    output.printDoctorHeader();

    var pass: usize = 0;
    var warn: usize = 0;
    var fail: usize = 0;

    // Platform
    const os = platform.Os.current();
    const arch = platform.Arch.current();
    output.printCheckPass("OS", os.name()); pass += 1;
    output.printCheckPass("Arch", arch.goName()); pass += 1;

    // Shell
    const sh = platform.Shell.detect();
    output.printCheckPass("Shell", sh.name()); pass += 1;

    // Package manager
    const pm = platform.PackageManager.detect();
    if (pm != .unknown) {
        output.printCheckPass("Package Manager", pm.command() orelse "unknown"); pass += 1;
    } else {
        output.printCheckWarn("Package Manager", "none detected"); warn += 1;
    }

    // Installed tools: verify binaries exist in ~/.local/bin
    output.printDoctorSection("Installed Tools");

    const home = std.posix.getenv("HOME") orelse "/tmp";
    var it = state.tools.iterator();
    while (it.next()) |kv| {
        const id = kv.key_ptr.*;
        const bin_path = std.fs.path.join(allocator, &.{ home, ".local", "bin", id }) catch continue;
        defer allocator.free(bin_path);

        if (std.fs.cwd().access(bin_path, .{})) |_| {
            output.printCheckPass(id, bin_path); pass += 1;
        } else |_| {
            output.printCheckFail(id, "binary missing from ~/.local/bin"); fail += 1;
        }
    }

    // Shell integration file
    output.printDoctorSection("Shell Integration");

    const integ_path = std.fs.path.join(allocator, &.{
        home, ".local", "bin", sh.integrationFileName(),
    }) catch null;
    if (integ_path) |p| {
        defer allocator.free(p);
        if (std.fs.cwd().access(p, .{})) |_| {
            output.printCheckPass("Integration file", p); pass += 1;
        } else |_| {
            output.printCheckWarn("Integration file", "not found (run a tool install to create it)"); warn += 1;
        }
    }

    // Plugin directory
    const plugin_dir = std.fs.path.join(allocator, &.{
        home, ".local", "share", "dot", "plugins",
    }) catch null;
    if (plugin_dir) |p| {
        defer allocator.free(p);
        if (std.fs.cwd().access(p, .{})) |_| {
            output.printCheckPass("Plugin dir", p); pass += 1;
        } else |_| {
            output.printCheckWarn("Plugin dir", "not found (created on first plugin install)"); warn += 1;
        }
    }

    output.printDoctorSummary(pass, warn, fail);
}
