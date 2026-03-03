const tool = @import("../tool.zig");

pub const def: tool.Tool = .{
    .id = "vault",
    .name = "Vault",
    .description = "Secrets management tool by HashiCorp",
    .groups = &.{.iac},
    .homepage = "https://www.vaultproject.io",
    .version_source = .{ .hashicorp = .{ .product = "vault" } },
    .strategy = .{ .hashicorp_release = .{ .product = "vault" } },
    .shell_completions = .{
        .bash_cmd = "complete -C vault vault",
        .zsh_cmd = "complete -C vault vault",
        .fish_cmd = null,
    },
    .quick_start = &.{
        "vault server -dev",
        "vault status",
        "vault secrets list",
        "vault kv put secret/myapp password=s3cr3t",
    },
    .resources = &.{
        .{ .label = "Docs", .url = "https://developer.hashicorp.com/vault/docs" },
        .{ .label = "Tutorials", .url = "https://developer.hashicorp.com/vault/tutorials" },
    },
};
