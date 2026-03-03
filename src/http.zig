const std = @import("std");

pub const Error = error{
    HttpError,
    InvalidUrl,
};

/// Fetch a URL and return the response body. Caller owns returned slice.
pub fn get(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &aw.writer,
    });

    const code = @intFromEnum(result.status);
    if (code < 200 or code >= 300) return error.HttpError;

    return aw.toOwnedSlice();
}

/// Download a URL to a file path. Creates parent directories as needed.
pub fn download(allocator: std.mem.Allocator, url: []const u8, dest_path: []const u8) !void {
    // Ensure parent directory exists
    if (std.fs.path.dirname(dest_path)) |dir| {
        std.fs.cwd().makePath(dir) catch {};
    }

    // Write to .tmp then rename for atomicity
    const tmp_path = try std.fmt.allocPrint(allocator, "{s}.tmp", .{dest_path});
    defer allocator.free(tmp_path);

    {
        var client: std.http.Client = .{ .allocator = allocator };
        defer client.deinit();

        const dest_file = try std.fs.cwd().createFile(tmp_path, .{});
        defer dest_file.close();

        var buf: [65536]u8 = undefined;
        var fw = dest_file.writer(&buf);

        const result = try client.fetch(.{
            .location = .{ .url = url },
            .response_writer = &fw.interface,
        });

        try fw.interface.flush();

        const code = @intFromEnum(result.status);
        if (code < 200 or code >= 300) {
            std.fs.cwd().deleteFile(tmp_path) catch {};
            return error.HttpError;
        }
    }

    try std.fs.cwd().rename(tmp_path, dest_path);
}
