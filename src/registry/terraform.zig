const tool = @import("../tool.zig");

pub const def: tool.Tool = .{
    .id = "terraform",
    .name = "Terraform",
    .description = "Infrastructure as Code tool by HashiCorp",
    .groups = &.{.iac},
    .homepage = "https://www.terraform.io",
    .brew_formula = "hashicorp/tap/terraform",
    .version_source = .{ .hashicorp = .{ .product = "terraform" } },
    .strategy = .{ .hashicorp_release = .{ .product = "terraform" } },
    .shell_completions = .{
        .bash_cmd = "complete -C terraform terraform",
        .zsh_cmd = "complete -C terraform terraform",
        .fish_cmd = null,
    },
    .quick_start = &.{
        "terraform init",
        "terraform plan",
        "terraform apply",
        "terraform destroy",
    },
    .resources = &.{
        .{ .label = "Docs", .url = "https://developer.hashicorp.com/terraform/docs" },
        .{ .label = "Registry", .url = "https://registry.terraform.io/" },
    },
};
