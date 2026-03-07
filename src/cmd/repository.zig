const std = @import("std");
const state_mod = @import("../state.zig");
const external = @import("../registry/external.zig");
const http = @import("../http.zig");
const output = @import("../ui/output.zig");

const HELP =
    \\Usage: dot repository <subcommand> [args]
    \\
    \\Manage external tool repositories.
    \\
    \\Subcommands:
    \\  add <url>          Add a repository from a URL
    \\  list               List registered repositories
    \\  remove <name>      Remove a repository by name
    \\  update [name]      Force-refresh one or all repositories
    \\
    \\Examples:
    \\  dot repository add https://raw.githubusercontent.com/me/dot-repo/main/repository.json
    \\  dot repository list
    \\  dot repository remove mytools
    \\  dot repository update
    \\  dot repository update mytools
    \\
;

pub fn run(allocator: std.mem.Allocator, args: []const []const u8, state: *state_mod.State) !void {
    _ = state;

    if (args.len == 0) {
        output.printRaw(HELP);
        return;
    }

    for (args) |a| {
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            output.printRaw(HELP);
            return;
        }
    }

    const subcmd = args[0];
    const rest = args[1..];

    if (std.mem.eql(u8, subcmd, "add")) {
        return cmdAdd(allocator, rest);
    } else if (std.mem.eql(u8, subcmd, "list")) {
        return cmdList(allocator);
    } else if (std.mem.eql(u8, subcmd, "remove") or std.mem.eql(u8, subcmd, "rm")) {
        return cmdRemove(allocator, rest);
    } else if (std.mem.eql(u8, subcmd, "update")) {
        return cmdUpdate(allocator, rest);
    } else {
        output.printFmt("Unknown repository subcommand: {s}\nRun 'dot repository --help' for usage.\n", .{subcmd});
    }
}

fn cmdAdd(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        output.printError("Usage: dot repository add <url>");
        return;
    }
    const url = args[0];

    std.debug.print("Fetching repository from {s}...\n", .{url});

    const body = http.get(allocator, url) catch |e| {
        output.printFmt("{s}Error:{s} could not fetch repository: {s}\n", .{ output.RED, output.RESET, @errorName(e) });
        return;
    };
    defer allocator.free(body);

    // Parse name from JSON
    const name = external.parseNameFromJson(allocator, body) catch |e| {
        output.printFmt("{s}Error:{s} repository JSON missing 'name' field ({s})\n", .{ output.RED, output.RESET, @errorName(e) });
        return;
    };
    defer allocator.free(name);

    const tool_count = external.countToolsInJson(allocator, body);

    // Load existing sources and check for duplicates
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const existing = external.loadRepositories(aa, allocator) catch &.{};
    for (existing) |s| {
        if (std.mem.eql(u8, s.name, name)) {
            output.printFmt("{s}Error:{s} repository '{s}' already added\n", .{ output.RED, output.RESET, name });
            return;
        }
    }

    // Write cache file
    const dir = try external.configDir(allocator);
    defer allocator.free(dir);
    try std.fs.cwd().makePath(dir);

    const cache_filename = try std.fmt.allocPrint(allocator, "repository-{s}.json", .{name});
    defer allocator.free(cache_filename);
    const cache_path = try std.fs.path.join(allocator, &.{ dir, cache_filename });
    defer allocator.free(cache_path);

    const cache_file = try std.fs.cwd().createFile(cache_path, .{});
    defer cache_file.close();
    try cache_file.writeAll(body);

    // Append to repositories.json
    const now = std.time.timestamp();
    const now_str = try std.fmt.allocPrint(aa, "{d}", .{now});

    var new_sources: std.ArrayList(external.RepositorySource) = .empty;
    try new_sources.appendSlice(aa, existing);
    try new_sources.append(aa, .{
        .name = try aa.dupe(u8, name),
        .url = try aa.dupe(u8, url),
        .added_at = now_str,
        .fetched_at = now_str,
    });

    try external.saveRepositories(allocator, new_sources.items);

    std.debug.print("{s}{s}{s} Added repository '{s}' — {d} tools available\n", .{
        output.GREEN, output.SYM_OK, output.RESET, name, tool_count,
    });
}

fn cmdList(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const sources = external.loadRepositories(aa, allocator) catch &.{};

    if (sources.len == 0) {
        std.debug.print("No repositories configured.\n\n", .{});
        std.debug.print("Add one with: dot repository add <url>\n", .{});
        return;
    }

    std.debug.print("\n{s}{s}External Repositories{s}\n\n", .{ output.CYAN, output.BOLD, output.RESET });
    std.debug.print("{s}{s:<20} {s:<8} {s:<24} {s}{s}\n", .{
        output.BOLD, "Name", "Tools", "Last Fetched", "URL", output.RESET,
    });
    std.debug.print("{s}", .{output.DIM});
    for (0..80) |_| std.debug.print(output.SYM_DASH, .{});
    std.debug.print("{s}\n", .{output.RESET});

    for (sources) |s| {
        // Count tools from cache
        const tool_count = blk: {
            const filename = std.fmt.allocPrint(allocator, "repository-{s}.json", .{s.name}) catch break :blk 0;
            defer allocator.free(filename);
            const dir = external.configDir(allocator) catch break :blk 0;
            defer allocator.free(dir);
            const path = std.fs.path.join(allocator, &.{ dir, filename }) catch break :blk 0;
            defer allocator.free(path);
            const file = std.fs.cwd().openFile(path, .{}) catch break :blk 0;
            defer file.close();
            const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch break :blk 0;
            defer allocator.free(content);
            break :blk external.countToolsInJson(allocator, content);
        };

        // Format fetched time
        const fetched_at_n = std.fmt.parseInt(i64, s.fetched_at, 10) catch 0;
        var date_buf: [32]u8 = undefined;
        const fetched_str: []const u8 = if (fetched_at_n == 0) "never" else blk: {
            const secs: u64 = @intCast(fetched_at_n);
            const epoch = std.time.epoch.EpochSeconds{ .secs = secs };
            const yd = epoch.getEpochDay().calculateYearDay();
            const md = yd.calculateMonthDay();
            break :blk std.fmt.bufPrint(&date_buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{
                yd.year, md.month.numeric(), md.day_index + 1,
            }) catch "?";
        };

        const url_trunc = s.url[0..@min(s.url.len, 40)];
        std.debug.print("{s:<20} {d:<8} {s:<24} {s}\n", .{
            s.name[0..@min(s.name.len, 19)], tool_count, fetched_str, url_trunc,
        });
    }

    std.debug.print("\n{d} repositor{s} configured\n\n", .{
        sources.len, if (sources.len == 1) "y" else "ies",
    });
}

fn cmdRemove(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        output.printError("Usage: dot repository remove <name>");
        return;
    }
    const name = args[0];

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const sources = external.loadRepositories(aa, allocator) catch &.{};

    var found = false;
    var new_sources: std.ArrayList(external.RepositorySource) = .empty;
    for (sources) |s| {
        if (std.mem.eql(u8, s.name, name)) {
            found = true;
        } else {
            try new_sources.append(aa, s);
        }
    }

    if (!found) {
        output.printFmt("{s}Error:{s} repository '{s}' not found\n", .{ output.RED, output.RESET, name });
        return;
    }

    try external.saveRepositories(allocator, new_sources.items);

    // Delete cache file
    const dir = external.configDir(allocator) catch null;
    if (dir) |d| {
        defer allocator.free(d);
        const filename = try std.fmt.allocPrint(allocator, "repository-{s}.json", .{name});
        defer allocator.free(filename);
        const path = try std.fs.path.join(allocator, &.{ d, filename });
        defer allocator.free(path);
        std.fs.cwd().deleteFile(path) catch {};
    }

    std.debug.print("{s}{s}{s} Removed repository '{s}'\n", .{ output.GREEN, output.SYM_OK, output.RESET, name });
}

fn cmdUpdate(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const sources = external.loadRepositories(aa, allocator) catch &.{};

    if (sources.len == 0) {
        std.debug.print("No repositories configured.\n", .{});
        return;
    }

    const target: ?[]const u8 = if (args.len > 0) args[0] else null;

    for (sources) |s| {
        if (target) |t| {
            if (!std.mem.eql(u8, s.name, t)) continue;
        }

        std.debug.print("Updating '{s}'...\n", .{s.name});
        external.fetchAndCache(allocator, s.name, s.url) catch |e| {
            std.debug.print("{s}{s}{s} {s}: fetch failed ({s}) — using cached\n", .{
                output.RED, output.SYM_FAIL, output.RESET, s.name, @errorName(e),
            });
            continue;
        };

        // Count tools in updated cache
        const tool_count = blk: {
            const filename = std.fmt.allocPrint(allocator, "repository-{s}.json", .{s.name}) catch break :blk 0;
            defer allocator.free(filename);
            const dir = external.configDir(allocator) catch break :blk 0;
            defer allocator.free(dir);
            const path = std.fs.path.join(allocator, &.{ dir, filename }) catch break :blk 0;
            defer allocator.free(path);
            const file = std.fs.cwd().openFile(path, .{}) catch break :blk 0;
            defer file.close();
            const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch break :blk 0;
            defer allocator.free(content);
            break :blk external.countToolsInJson(allocator, content);
        };

        std.debug.print("{s}{s}{s} {s}: {d} tools\n", .{
            output.GREEN, output.SYM_OK, output.RESET, s.name, tool_count,
        });
    }
}
