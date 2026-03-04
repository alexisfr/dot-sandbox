const tool = @import("../tool.zig");

pub const def: tool.Tool = .{
    .id = "jq",
    .name = "jq",
    .description = "Lightweight and flexible command-line JSON processor",
    .groups = &.{.utils},
    .homepage = "https://jqlang.github.io/jq/",
    .brew_formula = "jq",
    .version_source = .{ .github_release = .{ .repo = "jqlang/jq" } },
    .strategy = .{ .direct_binary = .{
        .url_template = "https://github.com/jqlang/jq/releases/download/{version}/jq-{os}-{arch}",
    } },
    .quick_start = &.{
        "echo '{\"key\": \"value\"}' | jq .key",
        "cat file.json | jq '.[] | .name'",
        "curl -s api.example.com/data | jq .",
    },
    .resources = &.{
        .{ .label = "Docs", .url = "https://jqlang.github.io/jq/manual/" },
        .{ .label = "Playground", .url = "https://jqplay.org/" },
    },
};
