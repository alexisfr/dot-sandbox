const tool = @import("../tool.zig");

pub const def: tool.Tool = .{
    .id = "oci",
    .name = "OCI CLI",
    .description = "Command line interface for Oracle Cloud Infrastructure",
    .groups = &.{.cloud},
    .homepage = "https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/",
    .brew_formula = "oci-cli",
    .version_source = .{ .pypi = .{ .package = "oci-cli" } },
    .strategy = .{ .pip_venv = .{
        .package = "oci-cli",
        .install_dir_rel = "~/.local/opt/oci-cli",
        .binary_name = "oci",
    } },
    .quick_start = &.{
        "oci setup config",
        "oci iam compartment list",
        "oci compute instance list",
        "oci os bucket list",
    },
    .resources = &.{
        .{ .label = "Docs", .url = "https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/" },
        .{ .label = "GitHub", .url = "https://github.com/oracle/oci-cli" },
    },
};
