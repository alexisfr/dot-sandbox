const std = @import("std");
const http = @import("../http.zig");
const platform = @import("../platform.zig");
const archive = @import("../archive.zig");
const output = @import("../ui/output.zig");
const state_mod = @import("../state.zig");
const tool_mod = @import("../tool.zig");
const version_mod = @import("../version.zig");
const progress_mod = @import("../ui/progress.zig");

const help =
    \\Usage: dot update [--force]
    \\
    \\Update dot itself to the latest release from GitHub.
    \\
    \\Options:
    \\  --force       Download and install even if already up to date
    \\  --help, -h    Show this help
    \\
    \\Examples:
    \\  dot update
    \\  dot update --force
    \\
;

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
) !void {
    var force = false;
    for (args) |a| {
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            output.printRaw(help);
            return;
        }
        if (std.mem.eql(u8, a, "--force")) force = true;
    }

    // Resolve latest version from GitHub
    std.debug.print("{s} Checking latest dot version...\n", .{output.sym_search});
    const version_source = tool_mod.VersionSource{ .github_release = .{ .repo = version_mod.github_repo } };
    const latest = version_source.resolve(allocator) catch |e| {
        const api_url = "https://api.github.com/repos/" ++ version_mod.github_repo ++ "/releases";
        switch (e) {
            error.VersionFetchFailed => {
                output.printFmt("{s}Error:{s} could not reach GitHub API\n", .{ output.red, output.reset });
                std.debug.print("  URL: {s}\n", .{api_url});
                std.debug.print("  The repository may be private, or you may be offline.\n", .{});
            },
            error.VersionNotFound => {
                output.printFmt("{s}Error:{s} no stable releases found\n", .{ output.red, output.reset });
                std.debug.print("  URL: {s}\n", .{api_url});
                std.debug.print("  No releases have been published yet.\n", .{});
            },
            error.VersionParseFailed => {
                output.printFmt("{s}Error:{s} unexpected response from GitHub API\n", .{ output.red, output.reset });
                std.debug.print("  URL: {s}\n", .{api_url});
            },
            else => output.printFmt("{s}Error:{s} {s}\n", .{ output.red, output.reset, @errorName(e) }),
        }
        return;
    };
    defer allocator.free(latest);

    const current = version_mod.current;

    if (!force and std.mem.eql(u8, current, latest)) {
        std.debug.print("\n{s}{s}{s} dot {s} — already up to date\n\n", .{
            output.green, output.sym_check, output.reset, current,
        });
        return;
    }

    std.debug.print("\n{s} {s}Updating dot{s} {s} → {s}\n\n", .{
        output.sym_install, output.bold, output.reset, current, latest,
    });

    const os_type = platform.OperatingSystem.current();
    const arch_type = platform.Arch.current();

    // Asset is a tarball named dot-{os}-{arch}.tar.gz (e.g. dot-linux-amd64.tar.gz).
    const url = try std.fmt.allocPrint(
        allocator,
        "https://github.com/{s}/releases/download/v{s}/dot-{s}-{s}.tar.gz",
        .{ version_mod.github_repo, latest, os_type.name(), arch_type.goName() },
    );
    defer allocator.free(url);

    // Temp directory for download and extraction
    const tmp_dir = try std.fmt.allocPrint(allocator, "/tmp/dot-update-{s}", .{latest});
    defer allocator.free(tmp_dir);
    std.fs.cwd().makePath(tmp_dir) catch {};
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};

    const archive_path = try std.fs.path.join(allocator, &.{ tmp_dir, "dot.tar.gz" });
    defer allocator.free(archive_path);

    // Download the tarball
    var bar = progress_mod.ProgressBar{ .step = "Downloading" };
    const progress = http.ProgressCallback{ .context = &bar, .func = progressCbFn };

    http.download(allocator, url, archive_path, progress) catch |e| {
        bar.finish();
        var status_buf: [32]u8 = undefined;
        const hint: []const u8 = switch (http.last_status) {
            404 => "release asset not found — the binary may not exist for your platform yet",
            403 => "access denied — repository may be private",
            0 => @errorName(e),
            else => std.fmt.bufPrint(&status_buf, "HTTP {d}", .{http.last_status}) catch @errorName(e),
        };
        output.printStep("Download", output.sym_fail, hint);
        output.printFmt("  URL: {s}\n", .{url});
        output.printError("Update failed");
        return error.CommandFailed;
    };
    bar.finish();

    // Extract
    const extract_dir = try std.fs.path.join(allocator, &.{ tmp_dir, "extract" });
    defer allocator.free(extract_dir);

    output.printStepStart("Extracting", "dot.tar.gz");
    archive.extractTarGz(archive_path, extract_dir, 0) catch |e| {
        output.printStepDone("Extracting", "failed");
        output.printFmt("{s}Error:{s} {s}\n", .{ output.red, output.reset, @errorName(e) });
        output.printError("Update failed");
        return error.CommandFailed;
    };
    output.printStepDone("Extracting", "dot.tar.gz");

    // The binary inside the tarball is named "dot"
    const src_bin = try std.fs.path.join(allocator, &.{ extract_dir, "dot" });
    defer allocator.free(src_bin);

    // Install path
    const home = std.posix.getenv("HOME") orelse "/tmp";
    const bin_dir = try std.fs.path.join(allocator, &.{ home, ".local", "bin" });
    defer allocator.free(bin_dir);
    std.fs.cwd().makePath(bin_dir) catch {};

    const dest = try std.fs.path.join(allocator, &.{ bin_dir, "dot" });
    defer allocator.free(dest);
    const tmp_dest = try std.fmt.allocPrint(allocator, "{s}.new", .{dest});
    defer allocator.free(tmp_dest);

    // Copy, chmod, atomic rename
    std.fs.cwd().copyFile(src_bin, std.fs.cwd(), tmp_dest, .{}) catch |e| {
        output.printStep("Install", output.sym_fail, @errorName(e));
        output.printError("Could not copy binary");
        return error.CommandFailed;
    };

    const chmod = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "chmod", "+x", tmp_dest },
    });
    allocator.free(chmod.stdout);
    allocator.free(chmod.stderr);

    std.fs.rename(std.fs.cwd(), tmp_dest, std.fs.cwd(), dest) catch |e| {
        output.printStep("Install", output.sym_fail, @errorName(e));
        output.printError("Could not replace binary");
        return error.CommandFailed;
    };

    output.printStep("Installed", output.sym_ok, dest);

    // Update state
    try state.addTool("dot", latest, "github_release", false);

    std.debug.print("\n{s}{s}{s} dot updated to {s}{s}{s}!\n\n", .{
        output.green, output.sym_check, output.reset,
        output.bold,  latest,           output.reset,
    });
}

fn progressCbFn(ctx: *anyopaque, done: u64, total: ?u64) void {
    const bar: *progress_mod.ProgressBar = @ptrCast(@alignCast(ctx));
    bar.update(done, total, "");
}
