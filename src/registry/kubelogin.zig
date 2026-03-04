const tool = @import("../tool.zig");

pub const def: tool.Tool = .{
    .id = "kubelogin",
    .name = "kubelogin",
    .description = "Kubernetes credential plugin for Azure/AAD authentication",
    .groups = &.{.k8s},
    .homepage = "https://github.com/Azure/kubelogin",
    .brew_formula = "int128/kubelogin/kubelogin",
    .version_source = .{ .github_release = .{ .repo = "Azure/kubelogin" } },
    .strategy = .{ .github_release = .{
        .url_template = "https://github.com/Azure/kubelogin/releases/download/v{version}/kubelogin-{os}-{arch}.zip",
        .binary_in_archive = "bin/{os}_{arch}/kubelogin",
    } },
    .quick_start = &.{
        "kubelogin convert-kubeconfig -l azurecli",
        "kubectl get pods",
    },
    .resources = &.{
        .{ .label = "GitHub", .url = "https://github.com/Azure/kubelogin" },
        .{ .label = "Docs", .url = "https://azure.github.io/kubelogin/" },
    },
};
