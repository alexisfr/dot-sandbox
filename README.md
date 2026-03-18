# dot — DevOps Toolbox

A fast, single-binary CLI tool manager for DevOps practitioners. Install and manage
helm, kubectl, terraform, jq and more — with shell completions and aliases configured
automatically.

Written in Zig 0.15.2 with no external dependencies.

## Install

```sh
# Build from source (requires Zig 0.15.2)
git clone https://github.com/the-devops-hub/dot
cd dot
zig build -Doptimize=ReleaseFast
sudo cp zig-out/bin/dot /usr/local/bin/dot
```

## Usage

```sh
dot list                        # Show all tools and their install status
dot install helm                # Install a tool
dot install --group k8s         # Install all tools in a group
dot upgrade                     # Upgrade all installed tools
dot upgrade helm                # Upgrade a specific tool
dot uninstall helm              # Remove a tool
dot status                      # Show installed versions, flag outdated
dot doctor                      # System health check
```

## Tools

| Tool | Groups | Description |
|------|--------|-------------|
| helm (h) | k8s | The Kubernetes Package Manager |
| kubectl (k) | k8s | The Kubernetes command-line tool |
| k9s | k8s | Terminal UI to interact with Kubernetes clusters |
| kubelogin | k8s | kubectl plugin for Kubernetes OIDC login |
| terraform (tf) | iac | Infrastructure as Code tool by HashiCorp |
| vault | iac | Secrets management tool by HashiCorp |
| jq | utils | Lightweight and flexible command-line JSON processor |
| gh | utils | GitHub's official command line tool |
| btop | utils | Resource monitor |
| podman | containers | Daemonless container engine |
| aws | cloud | AWS command line interface |
| gcloud | cloud | Google Cloud SDK |
| oci | cloud | Oracle Cloud Infrastructure CLI |
| starship | terminal | Cross-shell prompt |

## Groups

```sh
dot install --group k8s         # helm, kubectl, k9s, kubelogin
dot install --group iac         # terraform, vault
dot install --group cloud       # aws, gcloud, oci
dot install --group containers  # podman
dot install --group utils       # jq, gh, btop
dot install --group terminal    # starship
dot install --group all         # everything
```

## Shell integration

After installing a tool, dot writes completions and aliases to a shell integration
file sourced from your shell's RC file:

```
~/.local/bin/shell-integration.fish   # fish
~/.local/bin/shell-integration.zsh    # zsh
~/.local/bin/shell-integration.bash   # bash
```

Each tool gets a `# BEGIN TOOLNAME` / `# END TOOLNAME` block. Re-installing updates
the block in place — the rest of the file is untouched.

Aliases (e.g. `k` for kubectl, `h` for helm, `tf` for terraform) are set up with
completion delegation so tab-completion works on the alias too.

## Plugin system

dot supports external plugins following the kubectl/krew pattern — any executable
named `dot-<name>` on PATH is available as `dot <name>`:

```sh
dot plugin install https://github.com/user/dot-myplugin
dot plugin list
dot plugin uninstall myplugin
dot myplugin --help             # dispatches to dot-myplugin
```

Plugins are stored in `~/.local/share/dot/plugins/`.

## Adding a tool

Only two files need changing:

**1. Create `src/repository/<toolname>.zig`:**

```zig
const tool = @import("../tool.zig");

pub const def: tool.Tool = .{
    .id = "mytool",
    .name = "MyTool",
    .description = "Short description",
    .groups = &.{.utils},
    .homepage = "https://example.com",
    .brew_formula = "mytool",
    .version_source = .{ .github_release = .{ .repo = "owner/repo" } },
    .strategy = .{ .github_release = .{
        .url_template = "https://example.com/v{version}/mytool-{os}-{arch}.tar.gz",
        .binary_in_archive = "mytool",
    }},
    .shell_completions = .{
        .fish_cmd = "mytool completion fish | source",
        .zsh_cmd  = "source <(mytool completion zsh)",
        .bash_cmd = "source <(mytool completion bash)",
    },
};
```

**2. Add 2 lines to `src/repository/mod.zig`:**

```zig
const mytool = @import("mytool.zig");

pub const all_tools: []const *const tool.Tool = &.{
    // ...existing entries...
    &mytool.def,
};
```

## State

Installed tool state is persisted to `~/.config/dot/state.json`.

## Building and testing

```sh
zig build                       # Build → zig-out/bin/dot
zig build test --summary all    # Run all tests
zig build run -- list           # Build and run with args
```

Requires **Zig 0.15.2**.

## License

MIT
