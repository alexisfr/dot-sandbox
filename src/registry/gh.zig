const tool = @import("../tool.zig");

pub const def: tool.Tool = .{
    .id = "gh",
    .name = "GitHub CLI",
    .description = "GitHub's official command line tool",
    .groups = &.{.utils},
    .homepage = "https://cli.github.com",
    .brew_formula = "gh",
    .version_source = .{ .github_release = .{ .repo = "cli/cli" } },
    .strategy = .{ .github_release = .{
        .url_template = "https://github.com/cli/cli/releases/download/v{version}/gh_{version}_{os}_{arch}.tar.gz",
        .binary_in_archive = "gh_{version}_{os}_{arch}/bin/gh",
    } },
    .shell_completions = .{
        .bash_cmd = "source <(gh completion -s bash)",
        .zsh_cmd = "source <(gh completion -s zsh)",
        .fish_cmd = "gh completion -s fish | source",
    },
    .quick_start = &.{
        "gh auth login",
        "gh repo clone owner/repo",
        "gh pr create --title 'My PR' --body 'Description'",
        "gh issue list",
    },
    .resources = &.{
        .{ .label = "Docs", .url = "https://cli.github.com/manual/" },
        .{ .label = "GitHub", .url = "https://github.com/cli/cli" },
    },
};
