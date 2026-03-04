const tool = @import("../tool.zig");

pub const def: tool.Tool = .{
    .id = "k9s",
    .name = "k9s",
    .description = "Terminal UI to interact with Kubernetes clusters",
    .groups = &.{.k8s},
    .homepage = "https://k9scli.io",
    .brew_formula = "k9s",
    .version_source = .{ .github_release = .{ .repo = "derailed/k9s" } },
    .strategy = .{ .github_release = .{
        .url_template = "https://github.com/derailed/k9s/releases/download/v{version}/k9s_{os}_{arch}.tar.gz",
        .binary_in_archive = "k9s",
    } },
    .quick_start = &.{
        "k9s",
        "k9s --context my-cluster",
        "k9s --namespace kube-system",
    },
    .resources = &.{
        .{ .label = "Docs", .url = "https://k9scli.io/topics/commands/" },
        .{ .label = "GitHub", .url = "https://github.com/derailed/k9s" },
    },
};
