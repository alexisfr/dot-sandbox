# CLAUDE.md — dot (DevOps Toolbox)

dot is a CLI tool manager for DevOps practitioners — installs and manages CLI tools like helm,
kubectl, terraform, jq etc. Written in Zig 0.15.2 with no external dependencies.

## Commands

```bash
zig build                         # Build → zig-out/bin/dot
zig build test --summary all      # Run all tests
zig build run -- list             # Build and run with args
./zig-out/bin/dot list            # List tools + install status
./zig-out/bin/dot install helm    # Install helm (uses brew if available)
./zig-out/bin/dot install --group k8s   # Install all k8s tools
./zig-out/bin/dot status          # Show installed tools/versions
./zig-out/bin/dot doctor          # System health check
./zig-out/bin/dot upgrade         # Upgrade all installed tools
```

## Adding a New Tool

Only two files need changing:

1. **Create `src/registry/<toolname>.zig`**:

```zig
const tool = @import("../tool.zig");

pub const def: tool.Tool = .{
    .id = "mytool",
    .name = "MyTool",
    .description = "Short description",
    .groups = &.{.utils},
    .homepage = "https://example.com",
    .brew_formula = "mytool",           // optional: set if available on brew
    .version_source = .{ .github_release = .{
        .repo = "owner/repo",
        .filter = null,                 // optional prefix filter e.g. "v3."
    } },
    .strategy = .{ .github_release = .{
        .url_template = "https://example.com/v{version}/mytool-{os}-{arch}.tar.gz",
        .binary_in_archive = "mytool",
        .checksum_url_template = null,
    } },
    .shell_completions = .{
        .bash_cmd = "source <(mytool completion bash)",
        .zsh_cmd  = "source <(mytool completion zsh)",
        .fish_cmd = "mytool completion fish | source",
    },
};
```

2. **Add 2 lines to `src/registry/mod.zig`**:
```zig
const mytool = @import("mytool.zig");     // add import at top

pub const all_tools: []const *const tool.Tool = &.{
    // ...existing entries...
    &mytool.def,                          // add entry here
};
```

That's it. No other files need changing.

## Architecture

### Key Invariants

- **`src/ui/output.zig` owns all ANSI escape codes and emoji/symbol strings.** They are exported
  as `pub const` (e.g. `output.GREEN`, `output.SYM_OK`) so cmd files can reference them without
  hardcoding. `tool.zig` must only call named functions from `output` (no `std.debug.print`).
  cmd files may use `std.debug.print` for command-specific output but **must not hardcode** ANSI
  sequences or emoji literals — use `output.CYAN`, `output.SYM_CHECK`, etc. instead.
  Common print functions shared across commands (e.g. `printStep`, `printError`) live in `output.zig`;
  command-specific ones live in the respective `cmd/` file as private functions.

- **`InstallStrategy` is a union(enum)**. Each variant has its own `execute(ctx)` method in
  `src/tool.zig`. Do NOT add a god-function that switches on strategy type.

- **`VersionSource` is a union(enum)**. Each variant has its own `resolve(allocator)` method.
  No centralized if-else chain for version resolution.

- **The registry is comptime**. Tools live in `src/registry/<name>.zig` as `pub const def: tool.Tool`.
  They're collected into `all_tools: []const *const tool.Tool` in `src/registry/mod.zig`.

### VersionSource variants

| Variant | Description |
|---------|-------------|
| `github_release` | GitHub API latest release (optional `filter` prefix e.g. `"v3."`) |
| `hashicorp` | Hashicorp checkpoint API for terraform/vault |
| `k8s_stable_txt` | Fetches `https://dl.k8s.io/release/stable.txt` |
| `pypi` | PyPI JSON API |
| `static` | Hardcoded version string |

### InstallStrategy variants

| Variant | Description |
|---------|-------------|
| `github_release` | Download tar.gz/zip, extract, copy binary to `~/.local/bin/` |
| `direct_binary` | Download file directly as binary |
| `hashicorp_release` | Download from `releases.hashicorp.com` |
| `system_package` | Use native PM (apt, pacman, dnf, brew, etc.) |
| `pip_venv` | Create Python venv at `~/.local/opt/<name>`, symlink binary |
| `tarball` | Download tarball, run optional install script |

### Brew preference

If a tool has `brew_formula` set AND `brew` is available on the system, the install command
uses `brew install <formula>` (or `brew reinstall` with `--force`) instead of the native strategy.
This is checked in `src/cmd/install.zig`:`installTool()`.

### URL templates

`renderTemplate(allocator, template, ctx)` in `src/tool.zig` replaces:
- `{version}` — resolved version string (e.g. `3.15.0`, without leading `v`)
- `{os}` — `linux` or `darwin`
- `{arch}` — `amd64`, `arm64`, `arm`, `386`

Note: `{version}` does NOT include the leading `v` even if the GitHub tag has one.
The `v` must be baked into the URL template if required (e.g. `helm-v{version}-...`).

### Group install

Groups are defined in the `Group` enum in `src/tool.zig`:
`k8s`, `cloud`, `iac`, `containers`, `utils`, `terminal`

`dot install --group k8s` calls `registry.findByGroup(group, buf, &out)` then installs each tool.

### State

Persisted to `~/.config/dot/state.json`. Loaded on every command invocation.

- `State.init(allocator)` → loads JSON, populates `tools` and `plugins` HashMaps
- `State.save()` → serializes back to JSON
- `State.addTool(id, version, method)` → marks tool installed
- `State.isInstalled(id)` → bool check for list/status

### Shell integration

Shell config files are managed with boundary markers:
```
# BEGIN TOOLNAME
export PATH="..."
# END TOOLNAME
```
Functions in `src/shell.zig`: `ensurePluginPath`, `addToolConfig`, `removeToolConfig`.
Integration files: `~/.local/bin/shell-integration.{bash|zsh|fish}`

### Plugin system

Plugins are executables named `dot-<name>` in `~/.local/share/dot/plugins/`.
`dot foo` (unknown command) → checks PATH for `dot-foo` and execs it with remaining args.
`dot plugin install <url>` → git-clones and copies executable to plugin dir.

## Zig 0.15.2 API Notes

These differ from older Zig versions — compiler errors will be confusing without knowing these:

```zig
// ArrayList — UNMANAGED (pass allocator to every call)
var list: std.ArrayList(T) = .empty;
defer list.deinit(allocator);
try list.append(allocator, item);
const slice = try list.toOwnedSlice(allocator);

// HTTP fetch to memory
var client: std.http.Client = .{ .allocator = allocator };
defer client.deinit();
var aw: std.Io.Writer.Allocating = .init(allocator);
defer aw.deinit();
_ = try client.fetch(.{ .location = .{ .url = url }, .response_writer = &aw.writer });
const body = aw.writer.buffered();

// Stdout (std.io.getStdOut() is GONE)
const stdout = std.fs.File.stdout();
var buf: [4096]u8 = undefined;
var w = stdout.writer(&buf);
try w.interface.print("hello {s}\n", .{"world"});
try w.interface.flush();

// tar.gz extraction
var file_buf: [4096]u8 = undefined;
var fr = file.reader(&file_buf);
var decomp_buf: [std.compress.flate.max_window_len]u8 = undefined;
var decomp = std.compress.flate.Decompress.init(&fr.interface, .gzip, &decomp_buf);
try std.tar.pipeToFileSystem(dest_dir, &decomp.reader, .{ .strip_components = 1 });

// JSON parse
const parsed = try std.json.parseFromSlice(MyType, allocator, content, .{ .ignore_unknown_fields = true });
defer parsed.deinit();

// build.zig — use root_module (not root_source_file)
const root_mod = b.createModule(.{ .root_source_file = b.path("src/main.zig"), ... });
const exe = b.addExecutable(.{ .name = "dot", .root_module = root_mod });
```

**Other gotchas:**
- `std.io` → `std.Io` (capital I)
- No `std.mem.span([:0]u8)` — use `argv[i]` directly as `[]const u8`
- No `fmtSliceHexLower` — use `std.fmt.hex(integer)` for integers
- `build.zig.zon` requires a `fingerprint` field

## Memory Rules

```zig
// Always defer free immediately after allocPrint — never pass inline to a function
const s = try std.fmt.allocPrint(allocator, "foo {s}", .{bar});
defer allocator.free(s);
someFunction(s);   // safe

// std.process.Child.run always needs both stdout and stderr freed
const result = try std.process.Child.run(.{ ... });
defer allocator.free(result.stdout);
defer allocator.free(result.stderr);
```

Do NOT use `var` for values that are never mutated — the compiler errors on this.

## Tests

Tests are inline in source files (Zig convention). Currently in:
- `src/tool.zig` — `test "renderTemplate"`
- `src/registry/mod.zig` — registry lookup tests
- `src/platform.zig` — OS/arch/shell/PM detection smoke tests

Run: `zig build test --summary all`

After any change: `zig build` must compile clean and all tests must pass.
