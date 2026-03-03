const tool = @import("../tool.zig");

const helm = @import("helm.zig");
const kubectl = @import("kubectl.zig");
const k9s = @import("k9s.zig");
const kubelogin = @import("kubelogin.zig");
const jq = @import("jq.zig");
const gh = @import("gh.zig");
const terraform = @import("terraform.zig");
const vault = @import("vault.zig");
const btop = @import("btop.zig");
const podman = @import("podman.zig");
const aws = @import("aws.zig");
const gcloud = @import("gcloud.zig");
const oci_cli = @import("oci_cli.zig");
const starship = @import("starship.zig");

pub const all_tools: []const *const tool.Tool = &.{
    &helm.def,
    &kubectl.def,
    &k9s.def,
    &kubelogin.def,
    &jq.def,
    &gh.def,
    &terraform.def,
    &vault.def,
    &btop.def,
    &podman.def,
    &aws.def,
    &gcloud.def,
    &oci_cli.def,
    &starship.def,
};

pub fn findById(id: []const u8) ?*const tool.Tool {
    for (all_tools) |t| {
        if (std.mem.eql(u8, t.id, id)) return t;
    }
    return null;
}

/// Returns a comptime-length slice of tools in a given group.
/// Caller must supply a buffer for the results.
pub fn findByGroup(group: tool.Group, buf: []const *const tool.Tool, out: *[]const *const tool.Tool) void {
    var count: usize = 0;
    var result: [all_tools.len]*const tool.Tool = undefined;
    for (all_tools) |t| {
        for (t.groups) |g| {
            if (g == group) {
                result[count] = t;
                count += 1;
                break;
            }
        }
    }
    _ = buf;
    out.* = result[0..count];
}

const std = @import("std");

test "registry: all tools have IDs" {
    for (all_tools) |t| {
        try std.testing.expect(t.id.len > 0);
        try std.testing.expect(t.name.len > 0);
    }
}

test "registry: findById helm" {
    const t = findById("helm");
    try std.testing.expect(t != null);
    try std.testing.expectEqualStrings("helm", t.?.id);
}
