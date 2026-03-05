const std = @import("std");

const MAX_ID_LEN = 64;
const MAX_VERSION_LEN = 64;
const MAX_SOURCE_LEN = 2048;

/// Tool/plugin IDs: lowercase alphanumeric, hyphens, underscores only. Max 64 chars.
pub fn isValidToolId(id: []const u8) bool {
    if (id.len == 0 or id.len > MAX_ID_LEN) return false;
    for (id) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_') return false;
    }
    return true;
}

/// Version strings: alphanumeric, dots, hyphens, plus. No path separators or spaces.
pub fn isValidVersion(v: []const u8) bool {
    if (v.len == 0 or v.len > MAX_VERSION_LEN) return false;
    for (v) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '.' and c != '-' and c != '+') return false;
    }
    return true;
}

/// Plugin source: must begin with https://, http://, ./, or /.
pub fn isValidPluginSource(source: []const u8) bool {
    if (source.len == 0 or source.len > MAX_SOURCE_LEN) return false;
    if (std.mem.startsWith(u8, source, "https://")) return source.len > 8;
    if (std.mem.startsWith(u8, source, "http://")) return source.len > 7;
    if (std.mem.startsWith(u8, source, "./")) return source.len > 2;
    if (std.mem.startsWith(u8, source, "/")) return source.len > 1;
    return false;
}

/// Command names for plugin dispatch: alphanumeric and hyphens only. Prevents shell injection.
pub fn isValidCommandName(cmd: []const u8) bool {
    if (cmd.len == 0 or cmd.len > MAX_ID_LEN) return false;
    for (cmd) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '-') return false;
    }
    return true;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

test "isValidToolId: valid IDs" {
    try std.testing.expect(isValidToolId("helm"));
    try std.testing.expect(isValidToolId("kubectl"));
    try std.testing.expect(isValidToolId("my-tool"));
    try std.testing.expect(isValidToolId("my_tool"));
    try std.testing.expect(isValidToolId("tool123"));
    try std.testing.expect(isValidToolId("k9s"));
}

test "isValidToolId: invalid IDs" {
    try std.testing.expect(!isValidToolId(""));
    try std.testing.expect(!isValidToolId("tool with spaces"));
    try std.testing.expect(!isValidToolId("tool;rm -rf /"));
    try std.testing.expect(!isValidToolId("../evil"));
    try std.testing.expect(!isValidToolId("tool/path"));
    try std.testing.expect(!isValidToolId("tool\x00null"));
    try std.testing.expect(!isValidToolId("$(evil)"));
    // 65 chars — one over the limit
    try std.testing.expect(!isValidToolId("a" ** 65));
}

test "isValidVersion: valid versions" {
    try std.testing.expect(isValidVersion("3.15.0"));
    try std.testing.expect(isValidVersion("latest"));
    try std.testing.expect(isValidVersion("1.0.0-rc.1"));
    try std.testing.expect(isValidVersion("1.0.0+build.1"));
    try std.testing.expect(isValidVersion("v3.15.0"));
    try std.testing.expect(isValidVersion("2024.01.15"));
}

test "isValidVersion: invalid versions" {
    try std.testing.expect(!isValidVersion(""));
    try std.testing.expect(!isValidVersion("3.0/../../evil"));
    try std.testing.expect(!isValidVersion("1.0 && rm -rf /"));
    try std.testing.expect(!isValidVersion("$(evil)"));
    try std.testing.expect(!isValidVersion("1.0;evil"));
    try std.testing.expect(!isValidVersion("1.0\nnewline"));
    try std.testing.expect(!isValidVersion("a" ** 65));
}

test "isValidPluginSource: valid sources" {
    try std.testing.expect(isValidPluginSource("https://github.com/org/plugin.git"));
    try std.testing.expect(isValidPluginSource("http://example.com/plugin"));
    try std.testing.expect(isValidPluginSource("./my-plugin.sh"));
    try std.testing.expect(isValidPluginSource("/usr/local/bin/my-plugin"));
    try std.testing.expect(isValidPluginSource("./a"));
    try std.testing.expect(isValidPluginSource("/a"));
}

test "isValidPluginSource: invalid sources" {
    try std.testing.expect(!isValidPluginSource(""));
    try std.testing.expect(!isValidPluginSource("ftp://evil.com/plugin"));
    try std.testing.expect(!isValidPluginSource("plugin-name-only"));
    try std.testing.expect(!isValidPluginSource("https://"));
    try std.testing.expect(!isValidPluginSource("http://"));
    try std.testing.expect(!isValidPluginSource("./"));
    try std.testing.expect(!isValidPluginSource("/"));
    try std.testing.expect(!isValidPluginSource("ssh://git@github.com/org/repo"));
}

test "isValidCommandName: valid commands" {
    try std.testing.expect(isValidCommandName("my-cmd"));
    try std.testing.expect(isValidCommandName("install"));
    try std.testing.expect(isValidCommandName("list"));
    try std.testing.expect(isValidCommandName("plugin123"));
}

test "isValidCommandName: invalid commands" {
    try std.testing.expect(!isValidCommandName(""));
    try std.testing.expect(!isValidCommandName("cmd;evil"));
    try std.testing.expect(!isValidCommandName("cmd with spaces"));
    try std.testing.expect(!isValidCommandName("../evil"));
    try std.testing.expect(!isValidCommandName("cmd_underscore")); // underscores not allowed in commands
    try std.testing.expect(!isValidCommandName("$(evil)"));
    try std.testing.expect(!isValidCommandName("a" ** 65));
}
