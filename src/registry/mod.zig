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

/// Returns a slice of tools in a given group, written into caller-provided buf.
/// buf must have length >= all_tools.len.
pub fn findByGroup(group: tool.Group, buf: []*const tool.Tool, out: *[]const *const tool.Tool) void {
    var count: usize = 0;
    for (all_tools) |t| {
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

test "registry: findById unknown returns null" {
    try std.testing.expect(findById("not-a-real-tool") == null);
    try std.testing.expect(findById("") == null);
}

test "registry: findByGroup k8s returns non-empty" {
    var buf_arr: [all_tools.len]*const tool.Tool = undefined;
    const buf: []*const tool.Tool = &buf_arr;
    var results: []const *const tool.Tool = &.{};
    findByGroup(.k8s, buf, &results);
    try std.testing.expect(results.len > 0);
    // All returned tools must include the k8s group
    for (results) |t| {
        var found = false;
        for (t.groups) |g| {
            if (g == .k8s) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}

test "registry: findByGroup iac contains terraform and vault" {
    var buf_arr: [all_tools.len]*const tool.Tool = undefined;
    const buf: []*const tool.Tool = &buf_arr;
    var results: []const *const tool.Tool = &.{};
    findByGroup(.iac, buf, &results);
    try std.testing.expect(results.len > 0);
    var has_terraform = false;
    var has_vault = false;
    for (results) |t| {
        if (std.mem.eql(u8, t.id, "terraform")) has_terraform = true;
        if (std.mem.eql(u8, t.id, "vault")) has_vault = true;
    }
    try std.testing.expect(has_terraform);
    try std.testing.expect(has_vault);
}

test "registry: all tools have valid IDs (alphanumeric/hyphen/underscore)" {
    for (all_tools) |t| {
        for (t.id) |c| {
            try std.testing.expect(
                std.ascii.isAlphanumeric(c) or c == '-' or c == '_',
            );
        }
    }
}

test "registry: all tools have unique IDs" {
    for (all_tools, 0..) |a, i| {
        for (all_tools, 0..) |b, j| {
            if (i != j) {
                try std.testing.expect(!std.mem.eql(u8, a.id, b.id));
            }
        }
    }
}
