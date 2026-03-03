# dot — DevOps Toolbox Specification

## Commands

**Core**:
```
dot install <tool|group> [version] [--force]   # Install tool or group
dot install --group k8s                         # Install all tools in group
dot list [--group k8s]                          # Show tools + status
dot status                                      # Installed tools, versions, outdated
dot upgrade [tool]                              # Upgrade one or all tools
dot doctor                                      # System health check
dot --version / --help
```

**Plugin management** (kubectl/krew style):
```
dot plugin list                      # List installed dot plugins
dot plugin install <url|name>        # Install a plugin
dot plugin uninstall <name>          # Remove a plugin
dot plugin update [name]             # Update plugin(s)
dot <plugin-name> [args]             # Dispatch to dot-<plugin-name> if not builtin
```

**Future**: `dot theme list|install|use`

---

## Tool Groups

Groups allow batch installs. Each tool belongs to one or more groups.

| Group | Tools |
|-------|-------|
| `k8s` | helm, kubectl, k9s, kubelogin |
| `cloud` | aws-cli, gcloud, oci-cli |
| `iac` | terraform, vault |
| `containers` | podman |
| `utils` | jq, gh, btop |
| `terminal` | starship |
| `all` | everything above |

---

## Tool Definitions (all 14)

| Tool | Strategy | Version Source | Groups | Notes |
|------|----------|----------------|--------|-------|
| helm | github_release | github helm/helm (v3.x filter) | k8s | plugins: diff, secrets, git |
| kubectl | direct_binary | k8s CDN stable.txt | k8s | |
| k9s | github_release | github derailed/k9s | k8s | |
| kubelogin | github_release | github Azure/kubelogin | k8s | |
| aws-cli | tarball | AWS S3 URL | cloud | complex installer |
| gcloud | tarball | Google download URL | cloud | large tarball |
| oci-cli | pip_venv | PyPI | cloud | Python venv at ~/.local/opt/oci-cli |
| terraform | hashicorp_release | HashiCorp checkpoint API | iac | |
| vault | hashicorp_release | HashiCorp checkpoint API | iac | |
| jq | github_release | github jqlang/jq | utils | |
| gh | github_release | github cli/cli | utils | |
| btop | system_package | distro pkg mgr / github | utils | prefer system pkg |
| podman | system_package | distro pkg manager | containers | prefer system pkg |
| starship | github_release | github starship-rs/starship | terminal | |

---

## Package Manager Priority

When `system_package` strategy is used, dot tries managers in this order:
1. **Native distro**: pacman → apt → dnf → yum → zypper → apk (prefer native)
2. **brew** (Linuxbrew / Homebrew) — if available
3. **flatpak** — if available and tool has a Flatpak ID (avoid for CLIs when possible)
4. **snap** — last resort (PATH issues, container overhead)
5. **AppImage** — direct download fallback

For non-system-package tools (github_release, etc.): native distro PMs are irrelevant.

Rationale: native distro PMs integrate better with the system; brew is second choice on systems that have it (common on developer machines); flatpak/snap trade convenience for sandboxing overhead.

---

## Plugin System Design

Pattern: **kubectl/krew style** — plugins are executables named `dot-<name>` in PATH.

**Discovery**: `dot foo` → if `foo` not a builtin command → exec `dot-foo` with remaining args.

**Plugin install sources**:
- Git URL: `dot plugin install https://github.com/user/dot-oci-cost`
- Named (from curated registry): `dot plugin install oci-cost`
- Local path: `dot plugin install ./my-plugin`

**Plugin location**: `~/.local/share/dot/plugins/dot-<name>` (added to PATH via shell integration)

**Curated first-party plugins** (port from `devops-toolbox-old/utils/`):
- `dot-oci-cost` — GCP/OCI cost audit
- `dot-gcp-cleanup` — GCP resource cleanup

**Plugin state** (tracked in `state.json`):
```json
{
  "plugins": {
    "oci-cost": {
      "installed_at": "2026-02-22T10:30:00Z",
      "source_url": "https://github.com/user/dot-oci-cost",
      "version": "1.0.0"
    }
  }
}
```

---

## State Schema (`~/.config/dot/state.json`)

```json
{
  "version": "1.0",
  "tools": {
    "helm": {
      "version": "v3.15.0",
      "installed_at": "2026-02-22T10:30:00Z",
      "method": "github_release",
      "source": "~/.local/bin/helm",
      "status": "installed",
      "pinned": false,
      "tool_plugins": ["diff", "secrets", "git"]
    }
  },
  "plugins": {
    "oci-cost": {
      "installed_at": "2026-02-22T10:30:00Z",
      "source_url": "https://github.com/user/dot-oci-cost",
      "version": "1.0.0"
    }
  }
}
```

---

## Shell Integration Design

- Centralized file: `~/.local/bin/shell-integration.{bash|zsh|fish}`
- Sourced from `~/.bashrc` / `~/.zshrc` / `~/.config/fish/config.fish`
- Boundary markers: `# BEGIN HELM` ... `# END HELM`
- Plugin PATH: `~/.local/share/dot/plugins` added via `# BEGIN DOT_PLUGINS` marker
- Idempotent: re-run updates existing section

---

## UI Output Design

- Box header: `+----+` / `| Tool v1.0 Installation |`
- Steps: `emoji step_name           [status] detail`
- Emojis: 🔍 Pre-checks, 📥 Downloading, 🔐 Verification, 📦 Extraction, 🔧 Installation, 🐚 Shell, 🔌 Plugins, 🧹 Cleanup
- Progress bar: `📥 Downloading       [████████░░░░░] 60% (9/16MB)`
- Colors: CYAN steps, GREEN success, RED error, YELLOW in-progress

---

## Architecture

### File Layout

```
build.zig
build.zig.zon
SPEC.md
src/
  main.zig          # GPA allocator, call cli.run()
  cli.zig           # arg parse, dispatch commands + plugin fallback
  tool.zig          # Tool, Group, VersionSource, InstallStrategy types
  state.zig         # std.json load/save, full schema (tools + plugins)
  http.zig          # std.http.Client wrapper: get(url) -> []u8
  archive.zig       # std.compress.gzip + std.tar, std.zip
  platform.zig      # OS, Arch, Shell, PackageManager detection
  shell.zig         # boundary marker integration
  ui/
    output.zig      # printBox, printStep, printSuccess, printError
    progress.zig    # real-time progress bar (stderr)
  registry/
    mod.zig         # all_tools slice, findById(), findByGroup()
    helm.zig        # pub const def: Tool = .{ ... }
    kubectl.zig
    k9s.zig
    kubelogin.zig
    jq.zig
    gh.zig
    terraform.zig
    vault.zig
    btop.zig
    podman.zig
    aws.zig
    gcloud.zig
    oci_cli.zig
    starship.zig
  cmd/
    install.zig     # dot install <tool|--group k8s> [version] [--force]
    list.zig        # dot list [--group k8s]
    status.zig      # installed tools, versions, outdated flag
    doctor.zig      # system health check
    upgrade.zig     # dot upgrade [tool]
    plugin.zig      # dot plugin <list|install|uninstall|update>
```

### Key Types (`tool.zig`)

**`VersionSource`** — each tool carries its own resolution strategy:
```zig
pub const VersionSource = union(enum) {
    github_release: struct { repo: []const u8, filter: ?[]const u8 = null },
    hashicorp: struct { product: []const u8 },
    k8s_stable_txt: void,
    pypi: struct { package: []const u8 },
    static: struct { version: []const u8 },
};
```

**`InstallStrategy`** — self-contained per variant (no god installer file):
```zig
pub const InstallStrategy = union(enum) {
    github_release: struct { ... },
    direct_binary: struct { ... },
    hashicorp_release: struct { ... },
    system_package: struct { apt: ?[]const u8, pacman: ?[]const u8, ... },
    pip_venv: struct { ... },
    tarball: struct { ... },
};
```

**`Tool`** struct:
```zig
pub const Tool = struct {
    id: []const u8,
    name: []const u8,
    description: []const u8,
    groups: []const Group,
    homepage: []const u8,
    version_source: VersionSource,
    strategy: InstallStrategy,
    shell_completions: ?ShellCompletions,
    post_install: ?PostInstall,
    quick_start: []const []const u8,
    resources: []const Resource,
};
```

### Registry (comptime)

```zig
// registry/mod.zig
pub const all_tools: []const *const Tool = &.{
    &helm.def, &kubectl.def, &k9s.def, ...
};
pub fn findById(id: []const u8) ?*const Tool { ... }
pub fn findByGroup(group: Group) []const *const Tool { ... }
```

---

## Verification

End-to-end:
```bash
cd devops-toolbox && zig build
./zig-out/bin/dot list
./zig-out/bin/dot install --group k8s      # helm + kubectl + k9s + kubelogin
./zig-out/bin/dot install jq
./zig-out/bin/dot status                   # all installed, versions shown
./zig-out/bin/dot doctor                   # all checks green
./zig-out/bin/dot plugin install oci-cost
./zig-out/bin/dot oci-cost --help          # plugin dispatch works
cat ~/.config/dot/state.json | jq .        # valid JSON, all tools + plugins
cat ~/.local/bin/shell-integration.fish    # BEGIN/END sections present
```
