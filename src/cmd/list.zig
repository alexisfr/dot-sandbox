const std = @import("std");
const tool_mod = @import("../tool.zig");
const state_mod = @import("../state.zig");
const registry = @import("../registry/mod.zig");
const output = @import("../ui/output.zig");

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
) !void {
    var group_filter: ?tool_mod.Group = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--group") or std.mem.eql(u8, a, "-g")) {
            i += 1;
            if (i < args.len) group_filter = parseGroup(args[i]);
        }
    }

    output.printListHeader();

    var count: usize = 0;
    for (registry.all_tools) |t| {
        if (group_filter) |gf| {
            var in_group = false;
            for (t.groups) |g| {
                if (g == gf) { in_group = true; break; }
            }
            if (!in_group) continue;
        }

        var groups_buf: [64]u8 = undefined;
        var groups_str = std.io.fixedBufferStream(&groups_buf);
        const gw = groups_str.writer();
        for (t.groups, 0..) |g, idx| {
            if (idx > 0) gw.writeByte(',') catch {};
            gw.writeAll(@tagName(g)) catch {};
        }

        output.printListRow(t.id, t.description, state.isInstalled(t.id), groups_str.getWritten());
        count += 1;
    }

    const filter_name: ?[]const u8 = if (group_filter) |gf| @tagName(gf) else null;
    output.printListFooter(count, filter_name);
    _ = allocator;
}

fn parseGroup(name: []const u8) ?tool_mod.Group {
    if (std.mem.eql(u8, name, "k8s")) return .k8s;
    if (std.mem.eql(u8, name, "cloud")) return .cloud;
    if (std.mem.eql(u8, name, "iac")) return .iac;
    if (std.mem.eql(u8, name, "containers")) return .containers;
    if (std.mem.eql(u8, name, "utils")) return .utils;
    if (std.mem.eql(u8, name, "terminal")) return .terminal;
    return null;
}
