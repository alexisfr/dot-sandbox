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

/// Extract a .zip archive to a destination directory using std.zip.
pub fn extractZip(archive_path: []const u8, dest_path: []const u8) !void {
    try std.fs.cwd().makePath(dest_path);
    const dest_dir = try std.fs.cwd().openDir(dest_path, .{});

    const file = try std.fs.cwd().openFile(archive_path, .{});
    defer file.close();

    var file_buf: [4096]u8 = undefined;
    var file_reader = file.reader(&file_buf);

    try std.zip.extract(dest_dir, &file_reader, .{});
}
