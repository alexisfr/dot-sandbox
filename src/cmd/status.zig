const std = @import("std");
const state_mod = @import("../state.zig");
const output = @import("../ui/output.zig");

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    state: *state_mod.State,
) !void {
    _ = args;
    _ = allocator;

    output.printStatusHeader();

    if (state.tools.count() == 0) {
        output.printStatusEmpty();
        return;
    }

    var it = state.tools.iterator();
    while (it.next()) |kv| {
        const t = kv.value_ptr.*;
        output.printStatusRow(kv.key_ptr.*, t.version, t.installed_at, t.method);
    }

    output.printStatusFooter(state.tools.count());
}
