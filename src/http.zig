const std = @import("std");

pub const Error = error{
    HttpError,
    InvalidUrl,
};

/// Callback for download progress. context is passed back as-is to func.
pub const ProgressCallback = struct {
    context: *anyopaque,
    func: *const fn (context: *anyopaque, bytes_done: u64, total: ?u64) void,

    pub fn call(self: ProgressCallback, bytes_done: u64, total: ?u64) void {
        self.func(self.context, bytes_done, total);
    }
};

/// Fetch a URL and return the response body. Caller owns returned slice.
pub fn get(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    var alloc_writer: std.io.Writer.Allocating = .init(allocator);
    defer alloc_writer.deinit();

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &alloc_writer.writer,
    });

    const code = @intFromEnum(result.status);
    if (code < 200 or code >= 300) return error.HttpError;

    return alloc_writer.toOwnedSlice();
}

/// Download a URL to a file path with optional progress reporting.
/// Creates parent directories as needed. Writes to a .tmp file then renames
/// atomically on success.
pub fn download(
    allocator: std.mem.Allocator,
    url: []const u8,
    dest_path: []const u8,
    progress: ?ProgressCallback,
) !void {
    if (std.fs.path.dirname(dest_path)) |dir| {
        std.fs.cwd().makePath(dir) catch {};
    }

    const tmp_path = try std.fmt.allocPrint(allocator, "{s}.tmp", .{dest_path});
    defer allocator.free(tmp_path);

    errdefer std.fs.cwd().deleteFile(tmp_path) catch {};

    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    const uri = std.Uri.parse(url) catch return error.InvalidUrl;

    // Disable Accept-Encoding so the server sends raw bytes (archives are
    // already compressed; we don't want HTTP-level compression on top).
    var req = try client.request(.GET, uri, .{
        .headers = .{ .accept_encoding = .omit },
    });
    defer req.deinit();

    try req.sendBodiless();

    var redirect_buf: [8 * 1024]u8 = undefined;
    var response = try req.receiveHead(&redirect_buf);

    const code = @intFromEnum(response.head.status);
    if (code < 200 or code >= 300) return error.HttpError;

    const content_length: ?u64 = response.head.content_length;

    const dest_file = try std.fs.cwd().createFile(tmp_path, .{});
    defer dest_file.close();

    var file_buf: [65536]u8 = undefined;
    var file_writer = dest_file.writer(&file_buf);

    var transfer_buf: [65536]u8 = undefined;
    const reader = response.reader(&transfer_buf);

    var bytes_done: u64 = 0;
    while (true) {
        const bytes_read = reader.stream(&file_writer.interface, std.io.Limit.limited(65536)) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };
        bytes_done += bytes_read;
        if (bytes_read > 0) {
            if (progress) |cb| cb.call(bytes_done, content_length);
        }
    }

    // Final callback with total = bytes_done so the bar auto-completes even
    // when Content-Length was absent (indeterminate mode).
    if (progress) |cb| cb.call(bytes_done, content_length orelse bytes_done);

    try file_writer.interface.flush();
    try std.fs.cwd().rename(tmp_path, dest_path);
}
