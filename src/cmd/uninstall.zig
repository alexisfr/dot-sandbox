const std = @import("std");
const tool_mod = @import("../tool.zig");
const state_mod = @import("../state.zig");
const registry = @import("../registry/mod.zig");
const platform = @import("../platform.zig");
const shell_mod = @import("../shell.zig");
const output = @import("../ui/output.zig");
const validate = @import("../validate.zig");

const HELP =
    \\Usage: dot uninstall <tool>
    \\       dot remove <tool>
    \\
    \\Remove a tool installed by dot.
    \\
    \\Arguments:
    \\  <tool>    Tool ID to remove (e.g. helm, kubectl)
    \\
    \\Options:
    \\  --help, -h    Show this help
    \\
    \\What gets removed:
    \\  • Binary at ~/.local/bin/<tool>
    \\  • Shell completion section from the integration file
    \\  • Entry from ~/.config/dot/state.json
    \\
    \\Note: brew-installed tools are not removed from brew, only
    \\      unregistered from dot's state.
    \\
    \\Examples:
    \\  dot uninstall helm
    \\  dot remove terraform
    \\
;

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
) !void {
    if (args.len == 0) {
        output.printRaw(HELP);
        return;
    }

    for (args) |a| {
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            output.printRaw(HELP);
            return;
        }
    }

    const id = args[0];

    if (!validate.isValidToolId(id)) {
        output.printError("invalid tool name");
        return;
    }

    if (registry.findById(id) == null) {
        output.printUnknownTool(id);
        return;
    }

    if (!state.isInstalled(id)) {
        output.printFmt("{s} is not installed\n", .{id});
        return;
    }

    const home = std.posix.getenv("HOME") orelse return error.NoHome;

    // Remove binary from ~/.local/bin/
    const bin_path = try std.fs.path.join(allocator, &.{ home, ".local", "bin", id });
    defer allocator.free(bin_path);
    std.fs.cwd().deleteFile(bin_path) catch |e| switch (e) {
        error.FileNotFound => {}, // already gone, that's fine
        else => output.printWarning("could not remove binary"),
    };
    output.printStep("Cleanup", output.SYM_OK, bin_path);

    // Remove shell integration section
    const sh = platform.Shell.detect();
    if (sh != .unknown) {
        shell_mod.removeSection(sh, id, allocator) catch {};
        output.printStep("Shell integration", output.SYM_OK, "removed");
    }

    // Update state
    try state.removeTool(id);

    printToolUninstalled(id);
}

// ─── Uninstall-specific print functions ───────────────────────────────────────

fn printToolUninstalled(id: []const u8) void {
    std.debug.print("{s}{s}{s} {s} uninstalled\n", .{ output.GREEN, output.SYM_OK, output.RESET, id });
}

// ─── Tests ────────────────────────────────────────────────────────────────────

test "uninstall: unknown tool is rejected before state check" {
    // registry.findById("not-a-tool") == null, so run() returns early.
    // We verify this by checking the registry lookup directly.
    try std.testing.expect(registry.findById("not-a-tool") == null);
    try std.testing.expect(registry.findById("helm") != null);
}

test "uninstall: not-installed tool is a no-op on state" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmp.dir.realpath(".", &path_buf);
    const state_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/state.json", .{dir_path});
    defer std.testing.allocator.free(state_path);

    var state = try state_mod.State.initAt(std.testing.allocator, state_path);
    defer state.deinit();

    try std.testing.expect(!state.isInstalled("helm"));
    // Calling removeTool on something not in state should not error
    try state.removeTool("helm");
    try std.testing.expect(!state.isInstalled("helm"));
}

test "uninstall: removes tool from state" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmp.dir.realpath(".", &path_buf);
    const state_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/state.json", .{dir_path});
    defer std.testing.allocator.free(state_path);

    var state = try state_mod.State.initAt(std.testing.allocator, state_path);
    defer state.deinit();

    try state.addTool("helm", "3.15.0", "github_release", false);
    try std.testing.expect(state.isInstalled("helm"));
    try state.removeTool("helm");
    try std.testing.expect(!state.isInstalled("helm"));
}
