const std = @import("std");

pub const ToolEntry = struct {
    version: []const u8 = "",
    installed_at: []const u8 = "",
    method: []const u8 = "",
    source: []const u8 = "",
    status: []const u8 = "installed",
    pinned: bool = false,
    tool_plugins: []const []const u8 = &.{},
};

pub const PluginEntry = struct {
    installed_at: []const u8 = "",
    source_url: []const u8 = "",
    version: []const u8 = "",
};

/// In-memory representation of state.json.
pub const State = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    path: []u8,
    tools: std.StringHashMap(ToolEntry),
    plugins: std.StringHashMap(PluginEntry),

    pub fn init(allocator: std.mem.Allocator) !State {
        const home = std.posix.getenv("HOME") orelse "/tmp";
        const config_dir = try std.fs.path.join(allocator, &.{ home, ".config", "dot" });
        defer allocator.free(config_dir);
        try std.fs.cwd().makePath(config_dir);

        const path = try std.fs.path.join(allocator, &.{ config_dir, "state.json" });

        const arena = std.heap.ArenaAllocator.init(allocator);
        const tools = std.StringHashMap(ToolEntry).init(allocator);
        const plugins = std.StringHashMap(PluginEntry).init(allocator);

        var state = State{
            .allocator = allocator,
            .arena = arena,
            .path = path,
            .tools = tools,
            .plugins = plugins,
        };

        // Try to load existing state; ignore if missing
        state.load() catch |e| switch (e) {
            error.FileNotFound => {},
            else => {},
        };

        return state;
    }

    pub fn deinit(self: *State) void {
        self.tools.deinit();
        self.plugins.deinit();
        self.arena.deinit();
        self.allocator.free(self.path);
    }

    fn load(self: *State) !void {
        const file = try std.fs.cwd().openFile(self.path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.arena.allocator(), 4 * 1024 * 1024);

        const Schema = struct {
            version: []const u8 = "1.0",
            tools: ?std.json.Value = null,
            plugins: ?std.json.Value = null,
        };

        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.arena.allocator(),
            content,
            .{},
        );
        // parsed is owned by arena

        const root = parsed.value;
        if (root != .object) return;

        // Load tools
        if (root.object.get("tools")) |tools_val| {
            if (tools_val == .object) {
                var it = tools_val.object.iterator();
                while (it.next()) |kv| {
                    const tool_name = kv.key_ptr.*;
                    const tv = kv.value_ptr.*;
                    if (tv != .object) continue;

                    const entry = ToolEntry{
                        .version = if (tv.object.get("version")) |v| if (v == .string) v.string else "" else "",
                        .installed_at = if (tv.object.get("installed_at")) |v| if (v == .string) v.string else "" else "",
                        .method = if (tv.object.get("method")) |v| if (v == .string) v.string else "" else "",
                        .source = if (tv.object.get("source")) |v| if (v == .string) v.string else "" else "",
                        .status = if (tv.object.get("status")) |v| if (v == .string) v.string else "installed" else "installed",
                        .pinned = if (tv.object.get("pinned")) |v| if (v == .bool) v.bool else false else false,
                    };

                    try self.tools.put(tool_name, entry);
                }
            }
        }

        // Load plugins
        if (root.object.get("plugins")) |plugins_val| {
            if (plugins_val == .object) {
                var it = plugins_val.object.iterator();
                while (it.next()) |kv| {
                    const pv = kv.value_ptr.*;
                    if (pv != .object) continue;

                    const entry = PluginEntry{
                        .installed_at = if (pv.object.get("installed_at")) |v| if (v == .string) v.string else "" else "",
                        .source_url = if (pv.object.get("source_url")) |v| if (v == .string) v.string else "" else "",
                        .version = if (pv.object.get("version")) |v| if (v == .string) v.string else "" else "",
                    };

                    try self.plugins.put(kv.key_ptr.*, entry);
                }
            }
        }
        _ = Schema{};
    }

    pub fn save(self: *State) !void {
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(self.allocator);

        try buf.appendSlice(self.allocator, "{\n  \"version\": \"1.0\",\n  \"tools\": {\n");

        var first_tool = true;
        var tool_it = self.tools.iterator();
        while (tool_it.next()) |kv| {
            if (!first_tool) try buf.appendSlice(self.allocator, ",\n");
            first_tool = false;

            const t = kv.value_ptr.*;
            const line = try std.fmt.allocPrint(self.allocator,
                \\    "{s}": {{
                \\      "version": "{s}",
                \\      "installed_at": "{s}",
                \\      "method": "{s}",
                \\      "source": "{s}",
                \\      "status": "{s}",
                \\      "pinned": {s}
                \\    }}
            , .{
                kv.key_ptr.*,
                t.version,
                t.installed_at,
                t.method,
                t.source,
                t.status,
                if (t.pinned) "true" else "false",
            });
            defer self.allocator.free(line);
            try buf.appendSlice(self.allocator, line);
        }

        try buf.appendSlice(self.allocator, "\n  },\n  \"plugins\": {\n");

        var first_plugin = true;
        var plugin_it = self.plugins.iterator();
        while (plugin_it.next()) |kv| {
            if (!first_plugin) try buf.appendSlice(self.allocator, ",\n");
            first_plugin = false;

            const p = kv.value_ptr.*;
            const line = try std.fmt.allocPrint(self.allocator,
                \\    "{s}": {{
                \\      "installed_at": "{s}",
                \\      "source_url": "{s}",
                \\      "version": "{s}"
                \\    }}
            , .{ kv.key_ptr.*, p.installed_at, p.source_url, p.version });
            defer self.allocator.free(line);
            try buf.appendSlice(self.allocator, line);
        }

        try buf.appendSlice(self.allocator, "\n  }\n}\n");

        const file = try std.fs.cwd().createFile(self.path, .{});
        defer file.close();
        try file.writeAll(buf.items);
    }

    pub fn isInstalled(self: *State, id: []const u8) bool {
        return self.tools.contains(id);
    }

    pub fn getVersion(self: *State, id: []const u8) ?[]const u8 {
        const e = self.tools.get(id) orelse return null;
        return if (e.version.len > 0) e.version else null;
    }

    pub fn addTool(self: *State, id: []const u8, version: []const u8, method: []const u8) !void {
        const arena_alloc = self.arena.allocator();

        // ISO 8601 timestamp
        const ts = std.time.timestamp();
        const installed_at = try std.fmt.allocPrint(arena_alloc, "{d}", .{ts});

        const source = try std.fmt.allocPrint(
            arena_alloc,
            "~/.local/bin/{s}",
            .{id},
        );

        const key = try arena_alloc.dupe(u8, id);
        try self.tools.put(key, .{
            .version = try arena_alloc.dupe(u8, version),
            .installed_at = installed_at,
            .method = try arena_alloc.dupe(u8, method),
            .source = source,
            .status = "installed",
            .pinned = false,
        });
        try self.save();
    }

    pub fn removeTool(self: *State, id: []const u8) !void {
        _ = self.tools.remove(id);
        try self.save();
    }

    pub fn addPlugin(self: *State, name: []const u8, source_url: []const u8, version: []const u8) !void {
        const arena_alloc = self.arena.allocator();
        const ts = std.time.timestamp();
        const installed_at = try std.fmt.allocPrint(arena_alloc, "{d}", .{ts});

        const key = try arena_alloc.dupe(u8, name);
        try self.plugins.put(key, .{
            .installed_at = installed_at,
            .source_url = try arena_alloc.dupe(u8, source_url),
            .version = try arena_alloc.dupe(u8, version),
        });
        try self.save();
    }

    pub fn removePlugin(self: *State, name: []const u8) !void {
        _ = self.plugins.remove(name);
        try self.save();
    }
};
