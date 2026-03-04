const tool = @import("../tool.zig");

pub const def: tool.Tool = .{
    .id = "aws",
    .name = "AWS CLI",
    .description = "Unified command line interface for Amazon Web Services",
    .groups = &.{.cloud},
    .homepage = "https://aws.amazon.com/cli/",
    .brew_formula = "awscli",
    .version_source = .{ .github_release = .{ .repo = "aws/aws-cli" } },
    .strategy = .{ .tarball = .{
        .url_template = "https://awscli.amazonaws.com/awscli-exe-{os}-{arch}.zip",
        .strip_components = 0,
        .install_script = "aws/install",
    } },
    .quick_start = &.{
        "aws configure",
        "aws s3 ls",
        "aws ec2 describe-instances",
        "aws sso configure",
    },
    .resources = &.{
        .{ .label = "Docs", .url = "https://docs.aws.amazon.com/cli/latest/userguide/" },
        .{ .label = "Reference", .url = "https://awscli.amazonaws.com/v2/documentation/api/latest/index.html" },
    },
};
