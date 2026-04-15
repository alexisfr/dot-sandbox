# dot — The DevOps Toolbox

A single-binary CLI that installs and manages your DevOps tools — helm, kubectl,
terraform, jq and more — with shell completions and aliases wired up automatically.

## Why does this exist?

Great question. You probably shouldn't use this. You have options:

- **Homebrew** — works great, as long as you enjoy waiting for Ruby to update
  `libiconv` before you can install `kubectl`
- **Nix / NixOS** — the correct answer, assuming you have a week to write the
  derivation and a therapist on retainer
- **webi** — genuinely good, but then you'd have nothing to complain about at
  standup
- **mise / asdf** — excellent if your team already agrees on a version manager,
  which they don't
- **manual `curl | tar | mv`** — this is just `dot install` with extra steps

`dot` exists because sometimes you just want to run one command on a fresh VM,
get `kubectl`, `helm`, `terraform` and their completions, and go back to
actually doing your job.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/the-devops-hub/dot/main/install.sh | sh
```

Restart your shell (or `source ~/.zshrc` / `source ~/.config/fish/config.fish`), then:

```sh
dot install --group k8s     # kubectl, helm, k9s, kubelogin
dot install --group iac     # terraform, vault
dot install --group all     # everything, no regrets
```

## Commands

```sh
dot list                    # what's available
dot install <tool>          # install a tool
dot install --group <name>  # install a group
dot upgrade                 # upgrade everything
dot upgrade <tool>          # upgrade one thing
dot uninstall <tool>        # remove a tool
dot status                  # versions + outdated check
dot update                  # update dot itself
dot doctor                  # health check
```

## Groups

| Group | Tools |
|---|---|
| `k8s` | helm, kubectl, k9s, kubelogin |
| `iac` | terraform, opentofu, vault, tflint, terraform-docs, hcledit, terragrunt |
| `config` | ansible, gh |
| `cloud` | aws, gcloud, oci |
| `containers` | podman |
| `utils` | jq, yq, btop |
| `terminal` | starship |
| `all` | everything above |

## Shell integration

After installing a tool, dot writes completions and aliases to a shell integration
file sourced from your RC. Aliases like `k` (kubectl) and `tf` (terraform) get
completion delegation, so tab-complete works on the alias too.

## External repositories

Host your own tools as a JSON file and add them:

```sh
dot repository add https://example.com/my-tools/repository.json
dot repository list
dot repository update
dot repository remove my-tools
```

External tools override builtins with the same ID, so you can pin or replace anything.

## Build from source

Requires [Zig 0.15.2](https://ziglang.org/download/).

```sh
git clone https://github.com/the-devops-hub/dot
cd dot
zig build -Doptimize=ReleaseFast
cp zig-out/bin/dot ~/.local/bin/dot
```

## License

MIT
