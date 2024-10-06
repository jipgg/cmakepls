const std = @import("std");
const process = std.process;
const mem = std.mem;
const fs = std.fs;
const Allocator = std.mem.Allocator;
const Dir = fs.Dir;
const File = fs.File;
pub const CACHE_DIR: []const u8 = ".cmakepls_cache";
pub const LOCAL_DIR: []const u8 = ".cmakepls";
pub const KW_FORCED: []const u8 = "-FORCED";
pub const KW_VERBOSE: []const u8 = "-VERBOSE";
pub const DEFAULT_ALLOCATOR: Allocator = std.heap.page_allocator;
pub const APP_NAME: []const u8 = "cmakepls";
pub const CONFIG_FILE_NAME: []const u8 = "config.json";
pub const VERSION_MAJOR: u32 = 0;
pub const VERSION_MINOR: u32 = 0;
pub const VERSION_PATCH: u32 = 1;
pub const TEMPLATE_DIR_NAME: []const u8 = "templates";
pub const MAX_BYTES: usize = 1024 * 4;
pub const ParsedConfig = std.json.Parsed(ConfigFile);
pub const cstring = []const u8;
pub const ConfigFile = struct {
    toolchain: []const u8,
    defaults: struct {
        cxx_standard: cstring,
        cmake_minimum_required: cstring,
        export_compile_commands: cstring,
        cxx_standard_required: cstring,
        project: cstring,
        build_dir: cstring,
        source_dir: cstring,
        bin_dir: cstring,
        lib_dir: cstring,
    },
    place_compile_commands_in_workspace: bool,
};
pub const DEFAULT_CONFIG: ConfigFile = .{
    .toolchain = "null",
    .defaults = .{
        .project = "proj",
        .cmake_minimum_required = "3.22.2",
        .build_dir = "cmake-out",
        .cxx_standard = "17",
        .cxx_standard_required = "ON",
        .export_compile_commands = "ON",
        .source_dir = "src",
        .bin_dir = "bin",
        .lib_dir = "lib",
    },
    .place_compile_commands_in_workspace = true,
};
pub const Argv = struct {
    allocator: Allocator,
    data: [][:0]u8,
    pub fn init(allocator: Allocator) !Argv {
        return Argv{ .allocator = allocator, .data = try std.process.argsAlloc(allocator) };
    }
    pub fn deinit(self: Argv) void {
        std.process.argsFree(self.allocator, self.data);
    }
    pub fn keyword(self: Argv, comptime kw: []const u8) bool {
        for (self.data) |v| {
            if (std.mem.eql(u8, kw, v)) {
                return true;
            }
        }
        return false;
    }
    pub fn param(self: Argv, kw: []const u8) ?[]const u8 {
        for (self.data, 0..) |v, i| {
            const argi = i + 1;
            if (std.mem.eql(u8, kw, v)) {
                if (argi >= self.data.len) return null;
                return self.data[argi];
            }
        }
        return null;
    }
};

pub fn present_default_config(allocator: Allocator) !std.json.Parsed(ConfigFile) {
    var slice = std.ArrayList(u8).init(allocator);
    defer slice.deinit();
    try std.json.stringify(DEFAULT_CONFIG, .{ .whitespace = .indent_4 }, slice.writer());
    return try std.json.parseFromSlice(ConfigFile, allocator, slice.items, .{ .allocate = .alloc_always });
}
pub fn get_appdata_dir(allocator: Allocator) !std.fs.Dir {
    return open_appdata_dir(allocator) catch try make_appdata_dir(allocator);
}

pub fn open_appdata_dir(allocator: Allocator) !std.fs.Dir {
    const appdata_str = try std.fs.getAppDataDir(allocator, APP_NAME);
    defer allocator.free(appdata_str);
    return try std.fs.openDirAbsolute(appdata_str, .{ .no_follow = true });
}
pub fn make_appdata_dir(allocator: Allocator) !std.fs.Dir {
    const appdata_str = try std.fs.getAppDataDir(allocator, APP_NAME);
    defer allocator.free(appdata_str);
    try std.fs.makeDirAbsolute(appdata_str);
    return try open_appdata_dir(allocator);
}
pub fn open_local_dir(workspace: Dir) Dir.OpenError!Dir {
    return try workspace.openDir(LOCAL_DIR, .{ .no_follow = true });
}
pub fn make_local_dir(workspace: Dir) !Dir {
    try workspace.makeDir(LOCAL_DIR);
    return try workspace.openDir(LOCAL_DIR, .{ .no_follow = true });
}
pub fn has_local_dir(workspace: Dir) bool {
    var exists: ?Dir = open_local_dir(workspace) catch null;
    if (exists) |*v| {
        v.close();
        return true;
    } else return false;
}
pub fn get_local_config() !File {
    const local_dir = try open_local_dir();
    defer local_dir.close();
    try local_dir.openFile(CONFIG_FILE_NAME, .{});
}

pub fn read_config(allocator: Allocator, dir: Dir) !ParsedConfig {
    const file = try dir.openFile(CONFIG_FILE_NAME, .{ .mode = .read_only });
    const buf = try file.readToEndAlloc(allocator, MAX_BYTES);
    defer allocator.free(buf);
    return try std.json.parseFromSlice(ConfigFile, allocator, buf, .{ .allocate = .alloc_always });
}
/// user owns the returned data
pub fn read_global_config(allocator: Allocator) !ParsedConfig {
    const dir = try open_appdata_dir(allocator);
    const file = try dir.openFile(CONFIG_FILE_NAME, .{ .mode = .read_only });
    const buf = try file.readToEndAlloc(allocator, MAX_BYTES);
    defer allocator.free(buf);
    return try std.json.parseFromSlice(ConfigFile, allocator, buf, .{ .allocate = .alloc_always });
}
pub fn write_global_config(allocator: Allocator, config: ConfigFile) !void {
    var dir = open_appdata_dir(allocator) catch try make_appdata_dir(allocator);
    defer dir.close();
    const file = try dir.createFile(CONFIG_FILE_NAME, .{});
    defer file.close();
    try std.json.stringify(config, .{ .whitespace = .indent_4 }, file.writer());
}
pub fn get_config(allocator: Allocator, workspace: Dir) !ParsedConfig {
    var parsed: ?ParsedConfig = undefined;
    if (has_local_dir(workspace)) {
        var local_dir = try open_local_dir(workspace);
        defer local_dir.close();
        parsed = read_config(allocator, local_dir) catch read_global_config(allocator) catch null;
    } else {
        parsed = read_global_config(allocator) catch null;
    }
    if (parsed) |conf| return conf;
    try write_global_config(allocator, DEFAULT_CONFIG);
    return try read_global_config(allocator);
}
pub fn get_template_dir(a: Allocator, name: cstring) !Dir {
    var appdata_dir = try get_appdata_dir(a);
    defer appdata_dir.close();
    var templates_dir = try appdata_dir.openDir("templates", .{ .no_follow = true });
    defer templates_dir.close();
    return try templates_dir.openDir(name, .{ .iterate = true, .no_follow = true });
}
pub fn execute_command_slice(allocator: Allocator, cmd: []const []const u8, verbose: bool) !void {
    const rslt = try process.Child.run(.{
        .allocator = allocator,
        .argv = cmd,
    });
    defer {
        allocator.free(rslt.stderr);
        allocator.free(rslt.stdout);
    }
    if (verbose) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("{s}", .{rslt.stdout});
    }
    if (rslt.stderr.len > 0) {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("{s}", .{rslt.stderr});
    }
}
pub fn execute_command_str(allocator: Allocator, cmd: []const u8, verbose: bool) !void {
    try execute_command_slice(allocator, &[_][]const u8{cmd}, verbose);
}
pub fn delete_dir_contents(dir: Dir) !void {
    var it = dir.iterate();
    while (try it.next()) |v| {
        if (v.kind == .directory) {
            var child_dir = try dir.openDir(v.name, .{ .iterate = true });
            try delete_dir_contents(child_dir);
            child_dir.close();
        }
        try dir.deleteTree(v.name);
    }
}
pub fn copy_dir_recursively(src_dir: Dir, dest_dir: Dir) !void {
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
                try copy_dir_recursively(child_src_dir, child_dest_dir);
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
