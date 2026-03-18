# dot — The DevOps Toolbox

A fast, single-binary CLI tool manager for DevOps practitioners. Install and manage
helm, kubectl, terraform, jq and more — with shell completions and aliases wired up
automatically.

## Quick install

```sh
curl -fsSL https://raw.githubusercontent.com/the-devops-hub/dot/main/install.sh | sh
```

Then restart your shell or run `source ~/.config/fish/config.fish` (fish) / `source ~/.zshrc` (zsh).

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
file sourced from your RC file. Aliases (e.g. `k` for kubectl, `tf` for terraform)
get completion delegation so tab-complete works on the alias too.

## External repositories

dot supports external tool repositories — JSON files hosted anywhere:

```sh
dot repository add https://example.com/my-tools/repository.json
dot repository list
dot repository update
dot repository remove my-tools
```

## Build from source

Requires [Zig 0.15.2](https://ziglang.org/download/).

```sh
git clone https://github.com/the-devops-hub/dot
cd dot
zig build -Doptimize=ReleaseFast
sudo cp zig-out/bin/dot /usr/local/bin/dot
```

## License

MIT
