const std = @import("std");
const state_mod = @import("state.zig");
const install_cmd = @import("cmd/install.zig");
const list_cmd = @import("cmd/list.zig");
const status_cmd = @import("cmd/status.zig");
const doctor_cmd = @import("cmd/doctor.zig");
const upgrade_cmd = @import("cmd/upgrade.zig");
const uninstall_cmd = @import("cmd/uninstall.zig");
const repository_cmd = @import("cmd/repository.zig");
const output = @import("ui/output.zig");
const repo = @import("repository/loader.zig");
const tool_mod = @import("tool.zig");

const version = @import("version.zig");
const VERSION = "dot version " ++ version.CURRENT ++ "\n";

const HELP =
    \\
    \\+--------------------------------------------------+
    \\|  dot — DevOps Toolbox v0.1.0                     |
    \\+--------------------------------------------------+
    \\
    \\Usage: dot <command> [options]
    \\
    \\Commands:
    \\  install <tool> [version]    Install a tool (pin with explicit version)
    \\  install --group <group>     Install all tools in a group
    \\  uninstall <tool>            Uninstall a tool
    \\  list [--group <group>]      List available tools
    \\  status                      Show installed tools and versions
    \\  upgrade [tool|group]        Upgrade installed tools (skips pinned)
    \\  upgrade --force             Force upgrade, including pinned tools
    \\  doctor                      Check system health
    \\  repository <subcommand>      Manage external repositories
    \\
    \\Groups:  k8s, cloud, iac, containers, utils, terminal, all
    \\
    \\Repository subcommands:
    \\  repository add <url>
    \\  repository list
    \\  repository remove <name>
    \\  repository update [name]
    \\
    \\Options:
    \\  --version, -v         Show version
    \\  --help, -h            Show this help
    \\  <command> --help      Show help for a specific command
    \\
    \\
;

pub fn run(allocator: std.mem.Allocator, argv: [][:0]u8) !void {
    if (argv.len < 2) {
        output.printRaw(HELP);
        return;
    }

    const command: []const u8 = argv[1];

    if (std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "-v")) {
        output.printRaw(VERSION);
        return;
    }

    if (std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h") or std.mem.eql(u8, command, "help")) {
        output.printRaw(HELP);
        return;
    }

    // Convert argv[2..] to [][]const u8
    var rest: std.ArrayList([]const u8) = .empty;
    defer rest.deinit(allocator);
    for (argv[2..]) |a| {
        try rest.append(allocator, @as([]const u8, a));
    }
    const args = rest.items;

    // Commands that don't need the tool repository
    if (std.mem.eql(u8, command, "status")) {
        var state = try state_mod.State.init(allocator);
        defer state.deinit();
        return status_cmd.run(allocator, args, &state);
    }

    if (std.mem.eql(u8, command, "doctor")) {
        var state = try state_mod.State.init(allocator);
        defer state.deinit();
        return doctor_cmd.run(allocator, args, &state);
    }

    if (std.mem.eql(u8, command, "repository")) {
        var state = try state_mod.State.init(allocator);
        defer state.deinit();
        return repository_cmd.run(allocator, args, &state);
    }

    // Commands that need the merged tool list (builtins + external)
    var builtin = try repo.loadBuiltinTools(allocator);
    defer builtin.deinit();

    var external = try repo.loadExternalTools(allocator);
    defer external.deinit();

    const tools = try mergeTools(allocator, builtin.tools, external.tools);
    defer allocator.free(tools);

    if (std.mem.eql(u8, command, "list")) {
        var state = try state_mod.State.init(allocator);
        defer state.deinit();
        return list_cmd.run(allocator, args, &state, tools);
    }

    if (std.mem.eql(u8, command, "install")) {
        var state = try state_mod.State.init(allocator);
        defer state.deinit();
        return install_cmd.run(allocator, args, &state, tools);
    }

    if (std.mem.eql(u8, command, "upgrade")) {
        var state = try state_mod.State.init(allocator);
        defer state.deinit();
        return upgrade_cmd.run(allocator, args, &state, tools);
    }

    if (std.mem.eql(u8, command, "uninstall") or std.mem.eql(u8, command, "remove")) {
        var state = try state_mod.State.init(allocator);
        defer state.deinit();
        return uninstall_cmd.run(allocator, args, &state, tools);
    }

    // Suggest the closest known command if the edit distance is small enough.
    const known = [_][]const u8{ "list", "install", "uninstall", "status", "upgrade", "doctor", "repository" };
    var best_dist: usize = std.math.maxInt(usize);
    var best_cmd: []const u8 = "";
    for (known) |k| {
        const d = editDistance(command, k);
        if (d < best_dist) {
            best_dist = d;
            best_cmd = k;
        }
    }
    if (best_dist <= 3) {
        output.printFmt("Unknown command: {s}\nDid you mean '{s}'?\nRun 'dot --help' for usage.\n", .{ command, best_cmd });
    } else {
        output.printFmt("Unknown command: {s}\nRun 'dot --help' for usage.\n", .{command});
    }
}

/// Merge builtin tools with external tools. External tools override builtins with the same ID.
/// Caller owns the returned slice.
fn mergeTools(allocator: std.mem.Allocator, builtins: []const tool_mod.Tool, externals: []const tool_mod.Tool) ![]tool_mod.Tool {
    var list: std.ArrayList(tool_mod.Tool) = .empty;
    defer list.deinit(allocator);

    try list.appendSlice(allocator, builtins);

    for (externals) |ext| {
        var replaced = false;
        for (list.items, 0..) |item, i| {
            if (std.mem.eql(u8, item.id, ext.id)) {
                list.items[i] = ext;
                replaced = true;
                break;
            }
        }
        if (!replaced) try list.append(allocator, ext);
    }

    return list.toOwnedSlice(allocator);
}

/// Simple iterative Levenshtein distance, capped at 256-char inputs.
fn editDistance(a: []const u8, b: []const u8) usize {
    if (a.len == 0) return b.len;
    if (b.len == 0) return a.len;

    // Use two rows to avoid O(n*m) allocation.
    var prev: [257]usize = undefined;
    var curr: [257]usize = undefined;

    const blen = @min(b.len, 256);
    const alen = @min(a.len, 256);

    for (0..blen + 1) |j| prev[j] = j;

    for (0..alen) |i| {
        curr[0] = i + 1;
        for (0..blen) |j| {
            const cost: usize = if (a[i] == b[j]) 0 else 1;
            curr[j + 1] = @min(
                curr[j] + 1,
                @min(prev[j + 1] + 1, prev[j] + cost),
            );
        }
        const tmp = prev;
        prev = curr;
        curr = tmp;
    }

    return prev[blen];
}

// ─── Tests ────────────────────────────────────────────────────────────────────

test "editDistance: identical strings" {
    try std.testing.expectEqual(@as(usize, 0), editDistance("list", "list"));
}

test "editDistance: transposition costs 2" {
    // Levenshtein counts a swap as 2 ops (delete + insert); "lsit" vs "list" = 2
    try std.testing.expectEqual(@as(usize, 2), editDistance("lsit", "list"));
}

test "editDistance: one substitution" {
    try std.testing.expectEqual(@as(usize, 1), editDistance("lisT", "list"));
}

test "editDistance: one insertion" {
    try std.testing.expectEqual(@as(usize, 1), editDistance("ist", "list"));
}

test "editDistance: one deletion" {
    try std.testing.expectEqual(@as(usize, 1), editDistance("listt", "list"));
}

test "editDistance: empty strings" {
    try std.testing.expectEqual(@as(usize, 0), editDistance("", ""));
    try std.testing.expectEqual(@as(usize, 4), editDistance("", "list"));
    try std.testing.expectEqual(@as(usize, 4), editDistance("list", ""));
}

test "editDistance: completely different" {
    try std.testing.expect(editDistance("xyz", "list") > 3);
}

test "mergeTools: external overrides builtin with same ID" {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const builtin_tools = [_]tool_mod.Tool{
        .{
            .id = "helm",
            .name = "Helm",
            .description = "builtin",
            .groups = &.{.k8s},
            .homepage = "https://helm.sh",
            .version_source = .{ .static = .{ .version = "3.0.0" } },
            .strategy = .{ .direct_binary = .{ .url_template = "https://example.com" } },
        },
        .{
            .id = "kubectl",
            .name = "Kubectl",
            .description = "builtin",
            .groups = &.{.k8s},
            .homepage = "https://k8s.io",
            .version_source = .{ .static = .{ .version = "1.0.0" } },
            .strategy = .{ .direct_binary = .{ .url_template = "https://example.com" } },
        },
    };

    const ext_tools = [_]tool_mod.Tool{
        .{
            .id = "helm",
            .name = "Helm (external)",
            .description = "external override",
            .groups = &.{.k8s},
            .homepage = "https://helm.sh",
            .version_source = .{ .static = .{ .version = "4.0.0" } },
            .strategy = .{ .direct_binary = .{ .url_template = "https://example.com" } },
        },
        .{
            .id = "mytool",
            .name = "MyTool",
            .description = "external only",
            .groups = &.{.utils},
            .homepage = "https://example.com",
            .version_source = .{ .static = .{ .version = "1.0.0" } },
            .strategy = .{ .direct_binary = .{ .url_template = "https://example.com" } },
        },
    };

    const merged = try mergeTools(alloc, &builtin_tools, &ext_tools);
    defer alloc.free(merged);

    // Should have 3 tools: helm (overridden), kubectl, mytool
    try std.testing.expectEqual(@as(usize, 3), merged.len);

    // Find helm — should be the external version
    for (merged) |t| {
        if (std.mem.eql(u8, t.id, "helm")) {
            try std.testing.expectEqualStrings("external override", t.description);
        }
    }
}
