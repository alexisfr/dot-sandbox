const std = @import("std");
const http = @import("http.zig");
const platform = @import("platform.zig");
const archive = @import("archive.zig");
const output = @import("ui/output.zig");

pub const Group = enum { k8s, cloud, iac, containers, utils, terminal };

// ─── Version resolution ───────────────────────────────────────────────────────

pub const VersionSource = union(enum) {
    github_release: GithubRelease,
    hashicorp: Hashicorp,
    k8s_stable_txt: void,
    pypi: Pypi,
    static: Static,

    pub const GithubRelease = struct {
        repo: []const u8,
        /// If non-null, only tags that start with this prefix are considered.
        filter: ?[]const u8 = null,
        /// If non-null, strip this prefix from the tag to form the version string.
        /// e.g. strip_prefix = "jq-" turns tag "jq-1.8.1" into version "1.8.1".
        strip_prefix: ?[]const u8 = null,
    };

    pub const Hashicorp = struct {
        product: []const u8,
    };

    pub const Pypi = struct {
        package: []const u8,
    };

    pub const Static = struct {
        version: []const u8,
    };

    /// Fetch the latest version string. Caller owns the returned slice.
    pub fn resolve(self: VersionSource, allocator: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .github_release => |gh| resolveGithub(allocator, gh),
            .hashicorp => |h| resolveHashicorp(allocator, h),
            .k8s_stable_txt => resolveK8sStableTxt(allocator),
            .pypi => |p| resolvePypi(allocator, p),
            .static => |s| allocator.dupe(u8, s.version),
        };
    }

    fn resolveGithub(allocator: std.mem.Allocator, gh: GithubRelease) ![]u8 {
        const url = try std.fmt.allocPrint(
            allocator,
            "https://api.github.com/repos/{s}/releases",
            .{gh.repo},
        );
        defer allocator.free(url);

        const body = http.get(allocator, url) catch {
            return error.VersionFetchFailed;
        };
        defer allocator.free(body);

        // Parse JSON array of release objects
        const Release = struct {
            tag_name: []const u8 = "",
            prerelease: bool = false,
            draft: bool = false,
        };
        const parsed = std.json.parseFromSlice(
            []Release,
            allocator,
            body,
            .{ .ignore_unknown_fields = true },
        ) catch return error.VersionParseFailed;
        defer parsed.deinit();

        for (parsed.value) |rel| {
            if (rel.prerelease or rel.draft) continue;
            const tag = rel.tag_name;
            if (gh.filter) |prefix| {
                if (!std.mem.startsWith(u8, tag, prefix)) continue;
            }
            const ver = tagToVersion(tag, gh.strip_prefix);
            return allocator.dupe(u8, ver);
        }
        return error.VersionNotFound;
    }

    fn resolveHashicorp(allocator: std.mem.Allocator, h: Hashicorp) ![]u8 {
        const url = try std.fmt.allocPrint(
            allocator,
            "https://checkpoint-api.hashicorp.com/v1/check/{s}",
            .{h.product},
        );
        defer allocator.free(url);

        const body = http.get(allocator, url) catch return error.VersionFetchFailed;
        defer allocator.free(body);

        const Resp = struct {
            current_version: []const u8 = "",
        };
        const parsed = std.json.parseFromSlice(
            Resp,
            allocator,
            body,
            .{ .ignore_unknown_fields = true },
        ) catch return error.VersionParseFailed;
        defer parsed.deinit();

        return allocator.dupe(u8, parsed.value.current_version);
    }

    fn resolveK8sStableTxt(allocator: std.mem.Allocator) ![]u8 {
        const body = http.get(allocator, "https://dl.k8s.io/release/stable.txt") catch
            return error.VersionFetchFailed;
        defer allocator.free(body);

        const trimmed = std.mem.trim(u8, body, " \n\r\t");
        const ver = if (trimmed.len > 0 and trimmed[0] == 'v') trimmed[1..] else trimmed;
        return allocator.dupe(u8, ver);
    }

    fn resolvePypi(allocator: std.mem.Allocator, p: Pypi) ![]u8 {
        const url = try std.fmt.allocPrint(
            allocator,
            "https://pypi.org/pypi/{s}/json",
            .{p.package},
        );
        defer allocator.free(url);

        const body = http.get(allocator, url) catch return error.VersionFetchFailed;
        defer allocator.free(body);

        const Resp = struct {
            info: struct {
                version: []const u8 = "",
            } = .{},
        };
        const parsed = std.json.parseFromSlice(
            Resp,
            allocator,
            body,
            .{ .ignore_unknown_fields = true },
        ) catch return error.VersionParseFailed;
        defer parsed.deinit();

        return allocator.dupe(u8, parsed.value.info.version);
    }
};

// ─── Install strategies ───────────────────────────────────────────────────────

pub const InstallContext = struct {
    allocator: std.mem.Allocator,
    id: []const u8,
    version: []const u8,
    os: platform.Os,
    arch: platform.Arch,
    bin_dir: []const u8,
    tmp_dir: []const u8,
};

pub const InstallStrategy = union(enum) {
    github_release: GithubRelease,
    direct_binary: DirectBinary,
    hashicorp_release: HashicorpRelease,
    system_package: SystemPackage,
    pip_venv: PipVenv,
    tarball: Tarball,

    pub const GithubRelease = struct {
        /// URL with {version}, {os}, {arch} placeholders
        url_template: []const u8,
        /// Path within the archive to the binary, e.g. "{os}-{arch}/helm"
        binary_in_archive: []const u8,
        /// Optional checksum URL template
        checksum_url_template: ?[]const u8 = null,

        pub fn execute(self: GithubRelease, ctx: *InstallContext) !void {
            const url = try renderTemplate(ctx.allocator, self.url_template, ctx);
            defer ctx.allocator.free(url);

            const filename = std.fs.path.basename(url);
            const archive_path = try std.fs.path.join(ctx.allocator, &.{ ctx.tmp_dir, filename });
            defer ctx.allocator.free(archive_path);

            output.printDownloading(url);
            try http.download(ctx.allocator, url, archive_path);

            // Verify checksum if available
            if (self.checksum_url_template) |tmpl| {
                const csum_url = try renderTemplate(ctx.allocator, tmpl, ctx);
                defer ctx.allocator.free(csum_url);
                verifyChecksum(ctx.allocator, archive_path, csum_url) catch |e| {
                    output.printChecksumWarning(@errorName(e));
                };
            }

            // Extract
            const extract_dir = try std.fs.path.join(ctx.allocator, &.{ ctx.tmp_dir, "extract" });
            defer ctx.allocator.free(extract_dir);

            if (std.mem.endsWith(u8, archive_path, ".tar.gz") or
                std.mem.endsWith(u8, archive_path, ".tgz"))
            {
                try archive.extractTarGz(archive_path, extract_dir, 0);
            } else if (std.mem.endsWith(u8, archive_path, ".zip")) {
                try archive.extractZip(archive_path, extract_dir);
            }

            // Locate the binary in the extracted tree
            const bin_subpath = try renderTemplate(ctx.allocator, self.binary_in_archive, ctx);
            defer ctx.allocator.free(bin_subpath);

            const src_bin = try std.fs.path.join(ctx.allocator, &.{ extract_dir, bin_subpath });
            defer ctx.allocator.free(src_bin);

            try installBinary(ctx, src_bin);
        }
    };

    pub const DirectBinary = struct {
        /// URL with {version}, {os}, {arch} placeholders; download IS the binary
        url_template: []const u8,

        pub fn execute(self: DirectBinary, ctx: *InstallContext) !void {
            const url = try renderTemplate(ctx.allocator, self.url_template, ctx);
            defer ctx.allocator.free(url);

            const tmp_bin = try std.fs.path.join(ctx.allocator, &.{ ctx.tmp_dir, ctx.id });
            defer ctx.allocator.free(tmp_bin);

            output.printDownloading(url);
            try http.download(ctx.allocator, url, tmp_bin);

            try installBinary(ctx, tmp_bin);
        }
    };

    pub const HashicorpRelease = struct {
        product: []const u8,

        pub fn execute(self: HashicorpRelease, ctx: *InstallContext) !void {
            const url = try std.fmt.allocPrint(
                ctx.allocator,
                "https://releases.hashicorp.com/{s}/{s}/{s}_{s}_{s}_{s}.zip",
                .{
                    self.product,
                    ctx.version,
                    self.product,
                    ctx.version,
                    ctx.os.name(),
                    ctx.arch.goName(),
                },
            );
            defer ctx.allocator.free(url);

            const archive_path = try std.fmt.allocPrint(
                ctx.allocator,
                "{s}/{s}.zip",
                .{ ctx.tmp_dir, self.product },
            );
            defer ctx.allocator.free(archive_path);

            output.printDownloading(url);
            try http.download(ctx.allocator, url, archive_path);

            const extract_dir = try std.fmt.allocPrint(ctx.allocator, "{s}/extract", .{ctx.tmp_dir});
            defer ctx.allocator.free(extract_dir);

            try archive.extractZip(archive_path, extract_dir);

            const src_bin = try std.fs.path.join(ctx.allocator, &.{ extract_dir, self.product });
            defer ctx.allocator.free(src_bin);

            try installBinary(ctx, src_bin);
        }
    };

    pub const SystemPackage = struct {
        pacman: ?[]const u8 = null,
        apt: ?[]const u8 = null,
        dnf: ?[]const u8 = null,
        yum: ?[]const u8 = null,
        zypper: ?[]const u8 = null,
        apk: ?[]const u8 = null,
        brew: ?[]const u8 = null,
        flatpak: ?[]const u8 = null,
        snap: ?[]const u8 = null,

        pub fn execute(self: SystemPackage, ctx: *InstallContext) !void {
            const pm = platform.PackageManager.detect();
            const pkg_name = self.packageFor(pm) orelse {
                output.printNoPackageManager(@tagName(pm));
                return error.NoPackageForManager;
            };

            const install_args = pm.installArgs();
            var argv: std.ArrayList([]const u8) = .empty;
            defer argv.deinit(ctx.allocator);

            try argv.appendSlice(ctx.allocator, install_args);
            try argv.append(ctx.allocator, pkg_name);

            output.printRunningCmd(install_args[0], pkg_name);

            const result = try std.process.Child.run(.{
                .allocator = ctx.allocator,
                .argv = argv.items,
            });
            defer ctx.allocator.free(result.stdout);
            defer ctx.allocator.free(result.stderr);

            if (result.term.Exited != 0) {
                output.printDetail("Package install failed");
                return error.PackageInstallFailed;
            }
        }

        fn packageFor(self: SystemPackage, pm: platform.PackageManager) ?[]const u8 {
            return switch (pm) {
                .pacman => self.pacman,
                .apt => self.apt,
                .dnf => self.dnf,
                .yum => self.yum,
                .zypper => self.zypper,
                .apk => self.apk,
                .brew => self.brew,
                .flatpak => self.flatpak,
                .snap => self.snap,
                .unknown => null,
            };
        }
    };

    pub const PipVenv = struct {
        package: []const u8,
        /// Installation directory, e.g. "~/.local/opt/oci-cli"
        install_dir_rel: []const u8,
        /// Name of the binary inside the venv's bin/
        binary_name: []const u8,

        pub fn execute(self: PipVenv, ctx: *InstallContext) !void {
            const home = std.posix.getenv("HOME") orelse "/tmp";
            // Expand ~ manually
            const install_dir = if (std.mem.startsWith(u8, self.install_dir_rel, "~/"))
                try std.fs.path.join(ctx.allocator, &.{ home, self.install_dir_rel[2..] })
            else
                try ctx.allocator.dupe(u8, self.install_dir_rel);
            defer ctx.allocator.free(install_dir);

            // Create venv
            const venv_result = try std.process.Child.run(.{
                .allocator = ctx.allocator,
                .argv = &.{ "python3", "-m", "venv", install_dir },
            });
            defer ctx.allocator.free(venv_result.stdout);
            defer ctx.allocator.free(venv_result.stderr);
            if (venv_result.term.Exited != 0) return error.VenvCreationFailed;

            // pip install
            const pip = try std.fs.path.join(ctx.allocator, &.{ install_dir, "bin", "pip" });
            defer ctx.allocator.free(pip);

            const pip_result = try std.process.Child.run(.{
                .allocator = ctx.allocator,
                .argv = &.{ pip, "install", "--upgrade", self.package },
            });
            defer ctx.allocator.free(pip_result.stdout);
            defer ctx.allocator.free(pip_result.stderr);
            if (pip_result.term.Exited != 0) return error.PipInstallFailed;

            // Symlink binary to bin_dir
            const src = try std.fs.path.join(ctx.allocator, &.{ install_dir, "bin", self.binary_name });
            defer ctx.allocator.free(src);

            const dst = try std.fs.path.join(ctx.allocator, &.{ ctx.bin_dir, self.binary_name });
            defer ctx.allocator.free(dst);

            std.fs.cwd().makePath(ctx.bin_dir) catch {};
            std.fs.cwd().deleteFile(dst) catch {};
            try std.fs.cwd().symLink(src, dst, .{});
        }
    };

    pub const Tarball = struct {
        url_template: []const u8,
        /// strip_components for tar extraction
        strip_components: u32 = 1,
        /// Relative path within extracted dir to find the binary, or null for manual
        binary_rel_path: ?[]const u8 = null,
        /// If non-null, run this script relative to extracted dir instead
        install_script: ?[]const u8 = null,

        pub fn execute(self: Tarball, ctx: *InstallContext) !void {
            const url = try renderTemplate(ctx.allocator, self.url_template, ctx);
            defer ctx.allocator.free(url);

            const filename = std.fs.path.basename(url);
            const archive_path = try std.fs.path.join(ctx.allocator, &.{ ctx.tmp_dir, filename });
            defer ctx.allocator.free(archive_path);

            output.printDownloading(url);
            try http.download(ctx.allocator, url, archive_path);

            const extract_dir = try std.fmt.allocPrint(ctx.allocator, "{s}/extract", .{ctx.tmp_dir});
            defer ctx.allocator.free(extract_dir);

            if (std.mem.endsWith(u8, archive_path, ".tar.gz") or
                std.mem.endsWith(u8, archive_path, ".tgz"))
            {
                try archive.extractTarGz(archive_path, extract_dir, self.strip_components);
            } else if (std.mem.endsWith(u8, archive_path, ".zip")) {
                try archive.extractZip(archive_path, extract_dir);
            }

            if (self.install_script) |script| {
                const script_path = try std.fs.path.join(ctx.allocator, &.{ extract_dir, script });
                defer ctx.allocator.free(script_path);

                // Make executable
                const chmod_res = try std.process.Child.run(.{
                    .allocator = ctx.allocator,
                    .argv = &.{ "chmod", "+x", script_path },
                });
                ctx.allocator.free(chmod_res.stdout);
                ctx.allocator.free(chmod_res.stderr);

                const install_env = try std.fmt.allocPrint(
                    ctx.allocator,
                    "CLOUDSDK_INSTALL_DIR={s} {s} --quiet",
                    .{ ctx.bin_dir, script_path },
                );
                defer ctx.allocator.free(install_env);

                const res = try std.process.Child.run(.{
                    .allocator = ctx.allocator,
                    .argv = &.{ "sh", "-c", install_env },
                });
                defer ctx.allocator.free(res.stdout);
                defer ctx.allocator.free(res.stderr);
                if (res.term.Exited != 0) return error.InstallScriptFailed;
            } else if (self.binary_rel_path) |rel| {
                const src = try std.fs.path.join(ctx.allocator, &.{ extract_dir, rel });
                defer ctx.allocator.free(src);
                try installBinary(ctx, src);
            }
        }
    };

    pub fn execute(self: InstallStrategy, ctx: *InstallContext) !void {
        return switch (self) {
            .github_release => |s| s.execute(ctx),
            .direct_binary => |s| s.execute(ctx),
            .hashicorp_release => |s| s.execute(ctx),
            .system_package => |s| s.execute(ctx),
            .pip_venv => |s| s.execute(ctx),
            .tarball => |s| s.execute(ctx),
        };
    }
};

// ─── Tool definition ──────────────────────────────────────────────────────────

pub const ShellCompletions = struct {
    bash_cmd: ?[]const u8 = null,
    zsh_cmd: ?[]const u8 = null,
    fish_cmd: ?[]const u8 = null,

    pub fn forShell(self: ShellCompletions, shell: platform.Shell) ?[]const u8 {
        return switch (shell) {
            .bash => self.bash_cmd,
            .zsh => self.zsh_cmd,
            .fish => self.fish_cmd,
            .unknown => null,
        };
    }
};

pub const Resource = struct {
    label: []const u8,
    url: []const u8,
};

pub const Tool = struct {
    id: []const u8,
    name: []const u8,
    description: []const u8,
    groups: []const Group,
    homepage: []const u8,
    version_source: VersionSource,
    strategy: InstallStrategy,
    /// If set and brew is available, install via `brew install <formula>` instead
    /// of the native strategy. Use tap-prefixed names for third-party taps,
    /// e.g. "hashicorp/tap/terraform".
    brew_formula: ?[]const u8 = null,
    shell_completions: ?ShellCompletions = null,
    /// Short shell aliases written to the integration file, e.g. "k" → alias k=kubectl
    aliases: []const []const u8 = &.{},
    /// Shell commands to run after a fresh install (e.g. `helm plugin install ...`).
    /// Each entry is passed to `sh -c`. Failures are non-fatal.
    post_install: []const []const u8 = &.{},
    /// Shell commands to run after an upgrade (tool was already installed).
    /// Each entry is passed to `sh -c`. Failures are non-fatal.
    post_upgrade: []const []const u8 = &.{},
    quick_start: []const []const u8 = &.{},
    resources: []const Resource = &.{},
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Convert a GitHub tag_name to a clean version string.
/// Strips a leading 'v' unconditionally, then strips strip_prefix if provided.
/// e.g. "v3.15.0" → "3.15.0", "jq-1.8.1" with strip_prefix="jq-" → "1.8.1"
pub fn tagToVersion(tag: []const u8, strip_prefix: ?[]const u8) []const u8 {
    var ver = tag;
    if (ver.len > 0 and ver[0] == 'v') ver = ver[1..];
    if (strip_prefix) |pfx| {
        if (std.mem.startsWith(u8, ver, pfx)) ver = ver[pfx.len..];
    }
    return ver;
}

/// Replace {version}, {os}, {arch} placeholders in a template string.
pub fn renderTemplate(allocator: std.mem.Allocator, tmpl: []const u8, ctx: *const InstallContext) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    var i: usize = 0;
    while (i < tmpl.len) {
        if (tmpl[i] == '{') {
            const end = std.mem.indexOf(u8, tmpl[i..], "}") orelse {
                try result.append(allocator, tmpl[i]);
                i += 1;
                continue;
            };
            const key = tmpl[i + 1 .. i + end];
            const replacement: []const u8 = if (std.mem.eql(u8, key, "version"))
                ctx.version
            else if (std.mem.eql(u8, key, "os"))
                ctx.os.name()
            else if (std.mem.eql(u8, key, "arch"))
                ctx.arch.goName()
            else
                tmpl[i .. i + end + 1]; // keep unchanged

            try result.appendSlice(allocator, replacement);
            i += end + 1;
        } else {
            try result.append(allocator, tmpl[i]);
            i += 1;
        }
    }
    return result.toOwnedSlice(allocator);
}

/// Copy src_path binary to ctx.bin_dir/ctx.id and make it executable.
fn installBinary(ctx: *InstallContext, src_path: []const u8) !void {
    std.fs.cwd().makePath(ctx.bin_dir) catch {};

    const dest = try std.fs.path.join(ctx.allocator, &.{ ctx.bin_dir, ctx.id });
    defer ctx.allocator.free(dest);

    try std.fs.cwd().copyFile(src_path, std.fs.cwd(), dest, .{});

    const chmod = try std.process.Child.run(.{
        .allocator = ctx.allocator,
        .argv = &.{ "chmod", "+x", dest },
    });
    ctx.allocator.free(chmod.stdout);
    ctx.allocator.free(chmod.stderr);

    output.printInstalledTo(dest);
}

/// Fetch and verify SHA256 checksum from url against local file.
fn verifyChecksum(allocator: std.mem.Allocator, file_path: []const u8, checksum_url: []const u8) !void {
    const csum_body = try http.get(allocator, checksum_url);
    defer allocator.free(csum_body);

    // Parse "HASH  filename" format
    const first_space = std.mem.indexOf(u8, csum_body, " ") orelse return error.BadChecksumFormat;
    const expected_hex = std.mem.trim(u8, csum_body[0..first_space], " \n\r\t");

    if (expected_hex.len != 64) return error.BadChecksumFormat;

    // Hash the local file
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buf: [65536]u8 = undefined;
    while (true) {
        const n = try file.read(&buf);
        if (n == 0) break;
        hasher.update(buf[0..n]);
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    var actual_hex: [64]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (digest, 0..) |byte, i| {
        actual_hex[i * 2] = hex_chars[byte >> 4];
        actual_hex[i * 2 + 1] = hex_chars[byte & 0xf];
    }

    if (!std.mem.eql(u8, expected_hex, &actual_hex)) return error.ChecksumMismatch;
}

test "renderTemplate" {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var ctx = InstallContext{
        .allocator = alloc,
        .id = "helm",
        .version = "3.15.0",
        .os = .linux,
        .arch = .x86_64,
        .bin_dir = "/home/user/.local/bin",
        .tmp_dir = "/tmp/dot-helm",
    };

    const result = try renderTemplate(alloc, "helm-v{version}-{os}-{arch}.tar.gz", &ctx);
    defer alloc.free(result);

    try std.testing.expectEqualStrings("helm-v3.15.0-linux-amd64.tar.gz", result);
}

test "tagToVersion: strips leading v" {
    try std.testing.expectEqualStrings("3.15.0", tagToVersion("v3.15.0", null));
}

test "tagToVersion: no v prefix unchanged" {
    try std.testing.expectEqualStrings("3.15.0", tagToVersion("3.15.0", null));
}

test "tagToVersion: strip_prefix removes custom prefix" {
    try std.testing.expectEqualStrings("1.8.1", tagToVersion("jq-1.8.1", "jq-"));
}

test "tagToVersion: strip_prefix not present leaves tag unchanged" {
    try std.testing.expectEqualStrings("1.8.1", tagToVersion("1.8.1", "jq-"));
}

test "tagToVersion: v prefix stripped before strip_prefix applied" {
    // hypothetical: tag "vjq-1.0" with strip_prefix="jq-" → "1.0"
    try std.testing.expectEqualStrings("1.0", tagToVersion("vjq-1.0", "jq-"));
}

test "tagToVersion: empty tag" {
    try std.testing.expectEqualStrings("", tagToVersion("", null));
    try std.testing.expectEqualStrings("", tagToVersion("", "jq-"));
}
