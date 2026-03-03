const tool = @import("../tool.zig");

pub const def: tool.Tool = .{
    .id = "gcloud",
    .name = "Google Cloud SDK",
    .description = "Command line tools for Google Cloud Platform",
    .groups = &.{.cloud},
    .homepage = "https://cloud.google.com/sdk",
    .version_source = .{ .static = .{ .version = "latest" } },
    .strategy = .{ .tarball = .{
        .url_template = "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-{os}-{arch}.tar.gz",
        .strip_components = 1,
        .install_script = "install.sh",
    } },
    .shell_completions = .{
        .bash_cmd = "source ~/.local/bin/google-cloud-sdk/completion.bash.inc",
        .zsh_cmd = "source ~/.local/bin/google-cloud-sdk/completion.zsh.inc",
        .fish_cmd = null,
    },
    .quick_start = &.{
        "gcloud init",
        "gcloud auth login",
        "gcloud config set project MY_PROJECT",
        "gcloud compute instances list",
    },
    .resources = &.{
        .{ .label = "Docs", .url = "https://cloud.google.com/sdk/docs" },
        .{ .label = "Reference", .url = "https://cloud.google.com/sdk/gcloud/reference" },
    },
};
