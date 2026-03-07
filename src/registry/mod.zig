const std = @import("std");
const tool = @import("../tool.zig");

// Tool definitions now live in builtin-repository.json (embedded at compile time)
// and are loaded at runtime via registry/external.zig:loadBuiltinTools().
// This file is kept for utility functions that operate on a runtime tool slice.

pub fn findById(tools: []const tool.Tool, id: []const u8) ?tool.Tool {
    for (tools) |t| {
        if (std.mem.eql(u8, t.id, id)) return t;
    }
    return null;
}

/// Writes tools in the given group into `buf` and sets `out` to the filled prefix.
/// `buf` must be at least as long as `tools`.
pub fn findByGroup(tools: []const tool.Tool, group: tool.Group, buf: []tool.Tool, out: *[]const tool.Tool) void {
    var count: usize = 0;
    for (tools) |t| {
        for (t.groups) |g| {
            if (g == group) {
                buf[count] = t;
                count += 1;
                break;
            }
        }
    }
    out.* = buf[0..count];
}

test "findById: returns null for empty slice" {
    try std.testing.expect(findById(&.{}, "helm") == null);
}

test "findById: finds a tool by id" {
    const tools = [_]tool.Tool{.{
        .id = "helm",
        .name = "Helm",
        .description = "test",
        .groups = &.{.k8s},
        .homepage = "https://helm.sh",
        .version_source = .{ .static = .{ .version = "3.0.0" } },
        .strategy = .{ .direct_binary = .{ .url_template = "https://example.com" } },
    }};
    const t = findById(&tools, "helm");
    try std.testing.expect(t != null);
    try std.testing.expectEqualStrings("helm", t.?.id);
    try std.testing.expect(findById(&tools, "notexist") == null);
}

test "findByGroup: filters correctly" {
    const tools = [_]tool.Tool{
        .{
            .id = "helm",
            .name = "Helm",
            .description = "test",
            .groups = &.{.k8s},
            .homepage = "https://helm.sh",
            .version_source = .{ .static = .{ .version = "3.0.0" } },
            .strategy = .{ .direct_binary = .{ .url_template = "https://example.com" } },
        },
        .{
            .id = "jq",
            .name = "jq",
            .description = "test",
            .groups = &.{.utils},
            .homepage = "https://jqlang.github.io/jq/",
            .version_source = .{ .static = .{ .version = "1.7.0" } },
            .strategy = .{ .direct_binary = .{ .url_template = "https://example.com" } },
        },
    };
    var buf: [2]tool.Tool = undefined;
    var out: []const tool.Tool = &.{};
    findByGroup(&tools, .k8s, &buf, &out);
    try std.testing.expectEqual(@as(usize, 1), out.len);
    try std.testing.expectEqualStrings("helm", out[0].id);
}
