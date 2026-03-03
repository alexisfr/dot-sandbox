const tool = @import("../tool.zig");

pub const def: tool.Tool = .{
    .id = "btop",
    .name = "btop",
    .description = "Resource monitor that shows usage and stats for CPU, memory, disk and network",
    .groups = &.{.utils},
    .homepage = "https://github.com/aristocratos/btop",
    .version_source = .{ .github_release = .{ .repo = "aristocratos/btop" } },
    .strategy = .{ .system_package = .{
        .pacman = "btop",
        .apt = "btop",
        .dnf = "btop",
        .brew = "btop",
        .flatpak = "com.github.aristocratos.btop",
    } },
    .quick_start = &.{
        "btop",
    },
    .resources = &.{
        .{ .label = "GitHub", .url = "https://github.com/aristocratos/btop" },
    },
};
