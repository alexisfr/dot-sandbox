const tool = @import("../tool.zig");

pub const def: tool.Tool = .{
    .id = "podman",
    .name = "Podman",
    .description = "Daemonless container engine for OCI containers",
    .groups = &.{.containers},
    .homepage = "https://podman.io",
    .version_source = .{ .github_release = .{ .repo = "containers/podman" } },
    .strategy = .{ .system_package = .{
        .pacman = "podman",
        .apt = "podman",
        .dnf = "podman",
        .brew = "podman",
    } },
    .quick_start = &.{
        "podman pull ubuntu",
        "podman run -it ubuntu bash",
        "podman ps -a",
        "podman build -t myimage .",
    },
    .resources = &.{
        .{ .label = "Docs", .url = "https://docs.podman.io/" },
        .{ .label = "GitHub", .url = "https://github.com/containers/podman" },
    },
};
