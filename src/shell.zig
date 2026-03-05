const std = @import("std");
const platform = @import("platform.zig");

const LOCAL_BIN = "~/.local/bin";
const PLUGIN_DIR = "~/.local/share/dot/plugins";
const SOURCE_MARKER = "# SOURCE SHELL INTEGRATION";
const PATH_MARKER = "# ADD LOCAL BIN TO PATH";
const PLUGIN_PATH_MARKER = "# BEGIN DOT_PLUGINS";
const PLUGIN_PATH_END = "# END DOT_PLUGINS";

/// Ensure the centralized integration file is sourced from the shell's RC.
/// Idempotent.
pub fn ensureSourced(shell: platform.Shell, allocator: std.mem.Allocator) !void {
    const home = std.posix.getenv("HOME") orelse return error.NoHome;

    const rc_path = switch (shell) {
        .bash => try std.fs.path.join(allocator, &.{ home, ".bashrc" }),
        .zsh => try std.fs.path.join(allocator, &.{ home, ".zshrc" }),
        .fish => try std.fs.path.join(allocator, &.{ home, ".config", "fish", "config.fish" }),
        .unknown => return,
    };
    defer allocator.free(rc_path);

    const integration_path = try std.fs.path.join(
        allocator,
        &.{ home, ".local", "bin", shell.integrationFileName() },
    );
    defer allocator.free(integration_path);

    // Ensure integration file exists
    const integ_dir = std.fs.path.dirname(integration_path) orelse unreachable;
    try std.fs.cwd().makePath(integ_dir);
    const integ_file = try std.fs.cwd().createFile(integration_path, .{ .exclusive = false });
    integ_file.close();

    // Check if RC already sources our file
    const rc_content = std.fs.cwd().openFile(rc_path, .{}) catch |e| switch (e) {
        error.FileNotFound => {
            // Create RC and add source line
            try appendToFile(rc_path, try buildSourceLine(shell, integration_path, allocator));
            return;
        },
        else => return e,
    };
    const content = try rc_content.readToEndAlloc(allocator, 1024 * 1024);
    rc_content.close();
    defer allocator.free(content);

    if (std.mem.indexOf(u8, content, SOURCE_MARKER) != null) return; // already sourced

    const source_line = try buildSourceLine(shell, integration_path, allocator);
    defer allocator.free(source_line);
    try appendToFile(rc_path, source_line);

    // Also ensure PATH is set in integration file
    try ensurePathInIntegration(shell, integration_path, allocator, home);
}

/// Add (or update) a tool's shell config section in the integration file.
/// Uses # BEGIN TOOLNAME / # END TOOLNAME markers. Idempotent.
pub fn addSection(
    shell: platform.Shell,
    tool_name: []const u8,
    config: []const u8,
    allocator: std.mem.Allocator,
) !void {
    const home = std.posix.getenv("HOME") orelse return error.NoHome;
    const integration_path = try std.fs.path.join(
        allocator,
        &.{ home, ".local", "bin", shell.integrationFileName() },
    );
    defer allocator.free(integration_path);

    // Normalize to uppercase for markers
    const upper_name = try allocator.dupe(u8, tool_name);
    defer allocator.free(upper_name);
    for (upper_name) |*c| c.* = std.ascii.toUpper(c.*);

    const begin_marker = try std.fmt.allocPrint(allocator, "# BEGIN {s}", .{upper_name});
    defer allocator.free(begin_marker);
    const end_marker = try std.fmt.allocPrint(allocator, "# END {s}", .{upper_name});
    defer allocator.free(end_marker);

    const file = std.fs.cwd().openFile(integration_path, .{}) catch |e| switch (e) {
        error.FileNotFound => {
            const new_content = try std.fmt.allocPrint(allocator, "\n{s}\n{s}\n{s}\n", .{
                begin_marker,
                config,
                end_marker,
            });
            defer allocator.free(new_content);
            try writeFile(integration_path, new_content);
            return;
        },
        else => return e,
    };
    const existing = try file.readToEndAlloc(allocator, 4 * 1024 * 1024);
    file.close();
    defer allocator.free(existing);

    const new_content = try rebuildWithSection(existing, begin_marker, end_marker, config, allocator);
    defer allocator.free(new_content);
    try writeFile(integration_path, new_content);
}

/// Remove a tool's section from the integration file.
pub fn removeSection(
    shell: platform.Shell,
    tool_name: []const u8,
    allocator: std.mem.Allocator,
) !void {
    const home = std.posix.getenv("HOME") orelse return error.NoHome;
    const integration_path = try std.fs.path.join(
        allocator,
        &.{ home, ".local", "bin", shell.integrationFileName() },
    );
    defer allocator.free(integration_path);

    const upper_name = try allocator.dupe(u8, tool_name);
    defer allocator.free(upper_name);
    for (upper_name) |*c| c.* = std.ascii.toUpper(c.*);

    const begin_marker = try std.fmt.allocPrint(allocator, "# BEGIN {s}", .{upper_name});
    defer allocator.free(begin_marker);
    const end_marker = try std.fmt.allocPrint(allocator, "# END {s}", .{upper_name});
    defer allocator.free(end_marker);

    const file = std.fs.cwd().openFile(integration_path, .{}) catch return;
    const existing = try file.readToEndAlloc(allocator, 4 * 1024 * 1024);
    file.close();
    defer allocator.free(existing);

    const new_content = try rebuildWithoutSection(existing, begin_marker, end_marker, allocator);
    defer allocator.free(new_content);
    try writeFile(integration_path, new_content);
}

// ─── Pure text helpers (also used in tests) ───────────────────────────────────

/// Given existing file content, insert or replace the marked section with config.
/// Returns caller-owned slice.
pub fn rebuildWithSection(
    existing: []const u8,
    begin_marker: []const u8,
    end_marker: []const u8,
    config: []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    if (std.mem.indexOf(u8, existing, begin_marker) != null) {
        // Replace existing section
        var lines = std.mem.splitScalar(u8, existing, '\n');
        var in_section = false;
        while (lines.next()) |line| {
            if (std.mem.eql(u8, line, begin_marker)) {
                try out.appendSlice(allocator, begin_marker);
                try out.append(allocator, '\n');
                try out.appendSlice(allocator, config);
                try out.append(allocator, '\n');
                in_section = true;
            } else if (std.mem.eql(u8, line, end_marker)) {
                try out.appendSlice(allocator, end_marker);
                try out.append(allocator, '\n');
                in_section = false;
            } else if (!in_section) {
                try out.appendSlice(allocator, line);
                try out.append(allocator, '\n');
            }
        }
    } else {
        // Append new section
        try out.appendSlice(allocator, existing);
        if (existing.len > 0 and existing[existing.len - 1] != '\n') {
            try out.append(allocator, '\n');
        }
        try out.appendSlice(allocator, "\n");
        try out.appendSlice(allocator, begin_marker);
        try out.append(allocator, '\n');
        try out.appendSlice(allocator, config);
        try out.append(allocator, '\n');
        try out.appendSlice(allocator, end_marker);
        try out.append(allocator, '\n');
    }

    return out.toOwnedSlice(allocator);
}

/// Given existing file content, return new content with the marked section removed.
/// Returns caller-owned slice.
pub fn rebuildWithoutSection(
    existing: []const u8,
    begin_marker: []const u8,
    end_marker: []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    var lines = std.mem.splitScalar(u8, existing, '\n');
    var in_section = false;
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, begin_marker)) {
            in_section = true;
        } else if (std.mem.eql(u8, line, end_marker)) {
            in_section = false;
        } else if (!in_section) {
            try out.appendSlice(allocator, line);
            try out.append(allocator, '\n');
        }
    }

    return out.toOwnedSlice(allocator);
}

/// Ensure the plugin directory is in PATH in the integration file.
pub fn ensurePluginPath(shell: platform.Shell, allocator: std.mem.Allocator) !void {
    const home = std.posix.getenv("HOME") orelse return error.NoHome;
    const plugin_dir = try std.fs.path.join(allocator, &.{ home, ".local", "share", "dot", "plugins" });
    defer allocator.free(plugin_dir);

    const path_config = try shell.pathAddSyntax(plugin_dir, allocator);
    defer allocator.free(path_config);

    try addSection(shell, "DOT_PLUGINS", path_config, allocator);
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

fn buildSourceLine(shell: platform.Shell, integration_path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return switch (shell) {
        .fish => std.fmt.allocPrint(
            allocator,
            "\n{s}\nsource {s}\n",
            .{ SOURCE_MARKER, integration_path },
        ),
        else => std.fmt.allocPrint(
            allocator,
            "\n{s}\nsource {s}\n",
            .{ SOURCE_MARKER, integration_path },
        ),
    };
}

fn ensurePathInIntegration(
    shell: platform.Shell,
    integration_path: []const u8,
    allocator: std.mem.Allocator,
    home: []const u8,
) !void {
    const file = std.fs.cwd().openFile(integration_path, .{}) catch return;
    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch {
        file.close();
        return;
    };
    file.close();
    defer allocator.free(content);

    if (std.mem.indexOf(u8, content, PATH_MARKER) != null) return;

    const bin_dir = try std.fs.path.join(allocator, &.{ home, ".local", "bin" });
    defer allocator.free(bin_dir);

    const path_line = try shell.pathAddSyntax(bin_dir, allocator);
    defer allocator.free(path_line);

    const addition = try std.fmt.allocPrint(allocator, "\n{s}\n{s}\n", .{ PATH_MARKER, path_line });
    defer allocator.free(addition);

    try appendToFile(integration_path, addition);
}

fn appendToFile(path: []const u8, content: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = false });
    defer file.close();
    try file.seekFromEnd(0);
    try file.writeAll(content);
}

fn writeFile(path: []const u8, content: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(content);
}

// ─── Tests ────────────────────────────────────────────────────────────────────

test "rebuildWithSection: append to empty content" {
    const result = try rebuildWithSection(
        "",
        "# BEGIN HELM",
        "# END HELM",
        "source <(helm completion bash)",
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "# BEGIN HELM") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "# END HELM") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "source <(helm completion bash)") != null);
}

test "rebuildWithSection: append to existing content without section" {
    const existing = "export PATH=$PATH:/usr/local/bin\n";
    const result = try rebuildWithSection(
        existing,
        "# BEGIN HELM",
        "# END HELM",
        "source <(helm completion bash)",
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result);
    // Original content preserved
    try std.testing.expect(std.mem.indexOf(u8, result, "export PATH") != null);
    // Section appended
    try std.testing.expect(std.mem.indexOf(u8, result, "# BEGIN HELM") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "source <(helm completion bash)") != null);
}

test "rebuildWithSection: replace existing section" {
    const existing =
        "export PATH=$PATH:/usr/local/bin\n" ++
        "# BEGIN HELM\n" ++
        "source <(helm completion bash)\n" ++
        "# END HELM\n" ++
        "export EDITOR=vim\n";

    const result = try rebuildWithSection(
        existing,
        "# BEGIN HELM",
        "# END HELM",
        "source <(helm completion zsh)",
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result);
    // New content present
    try std.testing.expect(std.mem.indexOf(u8, result, "source <(helm completion zsh)") != null);
    // Old content removed
    try std.testing.expect(std.mem.indexOf(u8, result, "source <(helm completion bash)") == null);
    // Surrounding content preserved
    try std.testing.expect(std.mem.indexOf(u8, result, "export PATH") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "export EDITOR=vim") != null);
}

test "rebuildWithSection: idempotent on second apply" {
    const existing = "";
    const config = "source <(helm completion bash)";

    const first = try rebuildWithSection(existing, "# BEGIN HELM", "# END HELM", config, std.testing.allocator);
    defer std.testing.allocator.free(first);
    const second = try rebuildWithSection(first, "# BEGIN HELM", "# END HELM", config, std.testing.allocator);
    defer std.testing.allocator.free(second);

    // Marker appears exactly once
    var count: usize = 0;
    var it = std.mem.splitSequence(u8, second, "# BEGIN HELM");
    while (it.next()) |_| count += 1;
    try std.testing.expectEqual(@as(usize, 2), count); // split produces n+1 parts for n occurrences
}

test "rebuildWithoutSection: removes section" {
    const existing =
        "export PATH=$PATH:/usr/local/bin\n" ++
        "# BEGIN HELM\n" ++
        "source <(helm completion bash)\n" ++
        "# END HELM\n" ++
        "export EDITOR=vim\n";

    const result = try rebuildWithoutSection(existing, "# BEGIN HELM", "# END HELM", std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "# BEGIN HELM") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "# END HELM") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "source <(helm completion bash)") == null);
    // Surrounding content preserved
    try std.testing.expect(std.mem.indexOf(u8, result, "export PATH") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "export EDITOR=vim") != null);
}

test "rebuildWithoutSection: no-op if section absent" {
    const existing = "export PATH=$PATH:/usr/local/bin\nexport EDITOR=vim\n";
    const result = try rebuildWithoutSection(existing, "# BEGIN HELM", "# END HELM", std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "export PATH") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "export EDITOR=vim") != null);
}

test "rebuildWithoutSection: empty content stays empty-ish" {
    const result = try rebuildWithoutSection("", "# BEGIN HELM", "# END HELM", std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("\n", result); // splitScalar on "" produces one empty token
}
