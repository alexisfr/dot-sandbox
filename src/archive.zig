const std = @import("std");

/// Extract a .tar.gz archive to a destination directory.
/// strip_components: number of leading path components to strip (like tar --strip-components).
pub fn extractTarGz(archive_path: []const u8, dest_path: []const u8, strip_components: u32) !void {
    try std.fs.cwd().makePath(dest_path);
    const dest_dir = try std.fs.cwd().openDir(dest_path, .{});

    const file = try std.fs.cwd().openFile(archive_path, .{});
    defer file.close();

    var file_buf: [4096]u8 = undefined;
    var file_reader = file.reader(&file_buf);

    var decomp_buf: [std.compress.flate.max_window_len]u8 = undefined;
    var decomp = std.compress.flate.Decompress.init(&file_reader.interface, .gzip, &decomp_buf);

    try std.tar.pipeToFileSystem(dest_dir, &decomp.reader, .{
        .strip_components = strip_components,
    });
}

/// Extract a .zip archive to a destination directory using system `unzip`.
/// Using the system unzip preserves Unix file permissions stored in the archive.
pub fn extractZip(archive_path: []const u8, dest_path: []const u8, allocator: std.mem.Allocator) !void {
    try std.fs.cwd().makePath(dest_path);
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "unzip", "-o", "-q", archive_path, "-d", dest_path },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.term != .Exited or result.term.Exited != 0) return error.ExtractionFailed;
}

// ─── Tests ────────────────────────────────────────────────────────────────────
//
// Archive tests use system `tar`/`zip` to create fixtures. Both are available
// on any system this tool targets. If not found, the test is skipped via
// `return error.SkipZigTest`.

/// Run a shell command, return false if it fails or is not found.
fn runCmd(allocator: std.mem.Allocator, argv: []const []const u8) bool {
    const result = std.process.Child.run(.{ .allocator = allocator, .argv = argv }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    return result.term == .Exited and result.term.Exited == 0;
}

test "extractTarGz: single file, strip_components=0" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create a source file and pack it with system tar
    try tmp.dir.writeFile(.{ .sub_path = "hello.txt", .data = "hello world\n" });
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const archive = try std.fmt.allocPrint(allocator, "{s}/test.tar.gz", .{tmp_path});
    defer allocator.free(archive);

    if (!runCmd(allocator, &.{ "tar", "-czf", archive, "-C", tmp_path, "hello.txt" }))
        return error.SkipZigTest;

    // Extract into a subdirectory and verify
    const out = try std.fmt.allocPrint(allocator, "{s}/out", .{tmp_path});
    defer allocator.free(out);
    try extractTarGz(archive, out, 0);

    const content = try tmp.dir.readFileAlloc(allocator, "out/hello.txt", 4096);
    defer allocator.free(content);
    try std.testing.expectEqualStrings("hello world\n", content);
}

test "extractTarGz: strip_components=1 strips top-level directory" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("pkg");
    try tmp.dir.writeFile(.{ .sub_path = "pkg/binary", .data = "#!/bin/sh\n" });
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const archive = try std.fmt.allocPrint(allocator, "{s}/pkg.tar.gz", .{tmp_path});
    defer allocator.free(archive);

    if (!runCmd(allocator, &.{ "tar", "-czf", archive, "-C", tmp_path, "pkg" }))
        return error.SkipZigTest;

    const out = try std.fmt.allocPrint(allocator, "{s}/out", .{tmp_path});
    defer allocator.free(out);
    try extractTarGz(archive, out, 1); // strip "pkg/" prefix

    // "binary" should be at out/binary, not out/pkg/binary
    const content = try tmp.dir.readFileAlloc(allocator, "out/binary", 4096);
    defer allocator.free(content);
    try std.testing.expectEqualStrings("#!/bin/sh\n", content);
}

test "extractZip: single file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "data.txt", .data = "zip content\n" });
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const archive = try std.fmt.allocPrint(allocator, "{s}/test.zip", .{tmp_path});
    defer allocator.free(archive);
    const src = try std.fmt.allocPrint(allocator, "{s}/data.txt", .{tmp_path});
    defer allocator.free(src);

    if (!runCmd(allocator, &.{ "zip", "-j", archive, src }))
        return error.SkipZigTest;

    const out = try std.fmt.allocPrint(allocator, "{s}/out", .{tmp_path});
    defer allocator.free(out);
    try extractZip(archive, out, allocator);

    const content = try tmp.dir.readFileAlloc(allocator, "out/data.txt", 4096);
    defer allocator.free(content);
    try std.testing.expectEqualStrings("zip content\n", content);
}
