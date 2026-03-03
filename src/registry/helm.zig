const tool = @import("../tool.zig");

pub const def: tool.Tool = .{
    .id = "helm",
    .name = "Helm",
    .description = "The Kubernetes Package Manager",
    .groups = &.{.k8s},
    .homepage = "https://helm.sh",
    .version_source = .{ .github_release = .{
        .repo = "helm/helm",
        .filter = "v3.",
    } },
    .strategy = .{ .github_release = .{
        .url_template = "https://get.helm.sh/helm-v{version}-{os}-{arch}.tar.gz",
        .binary_in_archive = "{os}-{arch}/helm",
        .checksum_url_template = "https://get.helm.sh/helm-v{version}-{os}-{arch}.tar.gz.sha256sum",
    } },
    .shell_completions = .{
        .bash_cmd = "source <(helm completion bash)",
        .zsh_cmd = "source <(helm completion zsh)",
        .fish_cmd = "helm completion fish | source",
    },
    .post_install = .{ .helm_plugins = &.{
        "https://github.com/databus23/helm-diff",
        "https://github.com/jkroepke/helm-secrets",
        "https://github.com/aslafy-z/helm-git",
    } },
    .quick_start = &.{
        "helm repo add bitnami https://charts.bitnami.com/bitnami",
        "helm search repo nginx",
        "helm install my-nginx bitnami/nginx",
    },
    .resources = &.{
        .{ .label = "Docs", .url = "https://helm.sh/docs/" },
        .{ .label = "Hub", .url = "https://artifacthub.io/" },
        .{ .label = "Charts", .url = "https://github.com/bitnami/charts" },
    },
};
