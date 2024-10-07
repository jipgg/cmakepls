const std = @import("std");
pub fn field_names(comptime T: type) []const []const u8 {
    const fields = comptime std.meta.fields(T);
    var names: [fields.len][]const u8 = undefined;
    inline for (fields, 0..) |field, i| {
        names[i] = field.name;
    }
    return &names;
}
pub fn execute_command_slice(allocator: std.mem.Allocator, cmd: []const []const u8, verbose: bool) !void {
    const rslt = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = cmd,
    });
    defer {
        allocator.free(rslt.stderr);
        allocator.free(rslt.stdout);
    }
    if (verbose) {
        cout("{s}", .{rslt.stdout});
    }
    if (rslt.stderr.len > 0) {
        cerr("{s}", .{rslt.stderr});
        return std.process.Child.RunError.Unexpected;
    }
}
pub fn execute_command_str(allocator: std.mem.Allocator, cmd: []const u8, verbose: bool) !void {
    try execute_command_slice(allocator, &[_][]const u8{cmd}, verbose);
}
pub fn deep_clear_dir(dir: std.fs.Dir) !void {
    var it = dir.iterate();
    while (try it.next()) |v| {
        if (v.kind == .directory) {
            var child_dir = try dir.openDir(v.name, .{ .iterate = true });
            try deep_clear_dir(child_dir);
            child_dir.close();
        }
        try dir.deleteTree(v.name);
    }
}
pub fn deep_copy_dir(src_dir: std.fs.Dir, dest_dir: std.fs.Dir) !void {
    var it = src_dir.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .file => {
                try src_dir.copyFile(entry.name, dest_dir, entry.name, .{});
                continue;
            },
            .directory => {
                var child_src_dir = try src_dir.openDir(entry.name, .{
                    .iterate = true,
                    .no_follow = true,
                });
                defer child_src_dir.close();
                try dest_dir.makeDir(entry.name);
                var child_dest_dir = try dest_dir.openDir(entry.name, .{
                    .iterate = true,
                    .no_follow = true,
                });
                defer child_dest_dir.close();
                try deep_copy_dir(child_src_dir, child_dest_dir);
                continue;
            },
            .door => {},
            .unknown => {},
            .sym_link => {},
            .whiteout => {},
            .named_pipe => {},
            .event_port => {},
            .block_device => {},
            .character_device => {},
            .unix_domain_socket => {},
        }
        std.debug.print("Unhandled entry {any}", .{entry});
    }
}
pub inline fn cout(comptime format: []const u8, args: anytype) void {
    std.io.getStdOut().writer().print(comptime format, args) catch std.debug.print(comptime format, args);
}
pub inline fn cerr(comptime format: []const u8, args: anytype) void {
    std.io.getStdErr().writer().print(comptime format, args) catch std.debug.print(comptime format, args);
}
