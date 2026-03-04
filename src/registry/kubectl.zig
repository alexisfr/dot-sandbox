const tool = @import("../tool.zig");

pub const def: tool.Tool = .{
    .id = "kubectl",
    .name = "kubectl",
    .description = "The Kubernetes command-line tool",
    .groups = &.{.k8s},
    .homepage = "https://kubernetes.io/docs/reference/kubectl/",
    .brew_formula = "kubernetes-cli",
    .version_source = .{ .k8s_stable_txt = {} },
    .strategy = .{ .direct_binary = .{
        .url_template = "https://dl.k8s.io/release/v{version}/bin/{os}/{arch}/kubectl",
    } },
    .shell_completions = .{
        .bash_cmd = "source <(kubectl completion bash)",
        .zsh_cmd = "source <(kubectl completion zsh)",
        .fish_cmd = "kubectl completion fish | source",
    },
    .quick_start = &.{
        "kubectl get nodes",
        "kubectl get pods -A",
        "kubectl apply -f manifest.yaml",
    },
    .resources = &.{
        .{ .label = "Docs", .url = "https://kubernetes.io/docs/reference/kubectl/" },
        .{ .label = "Cheatsheet", .url = "https://kubernetes.io/docs/reference/kubectl/cheatsheet/" },
    },
};
