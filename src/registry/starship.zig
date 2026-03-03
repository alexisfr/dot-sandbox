const tool = @import("../tool.zig");

pub const def: tool.Tool = .{
    .id = "starship",
    .name = "Starship",
    .description = "The minimal, blazing-fast, and infinitely customizable prompt for any shell",
    .groups = &.{.terminal},
    .homepage = "https://starship.rs",
    .version_source = .{ .github_release = .{ .repo = "starship/starship" } },
    .strategy = .{ .github_release = .{
        .url_template = "https://github.com/starship/starship/releases/download/v{version}/starship-{arch}-unknown-{os}-musl.tar.gz",
        .binary_in_archive = "starship",
    } },
    .shell_completions = .{
        .bash_cmd = "eval \"$(starship init bash)\"",
        .zsh_cmd = "eval \"$(starship init zsh)\"",
        .fish_cmd = "starship init fish | source",
    },
    .quick_start = &.{
        "starship init bash",
        "starship config",
        "starship explain",
    },
    .resources = &.{
        .{ .label = "Docs", .url = "https://starship.rs/guide/" },
        .{ .label = "Config", .url = "https://starship.rs/config/" },
        .{ .label = "Presets", .url = "https://starship.rs/presets/" },
    },
};
