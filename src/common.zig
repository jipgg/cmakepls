const std = @import("std");
const Allocator = std.mem.Allocator;
const Dir = std.fs.Dir;
const process = std.process;
const mem = std.mem;
pub const CACHE_DIR = ".cmakepls_cache";
pub const KW_FORCED = "-FORCED";
pub const KW_VERBOSE = "-VERBOSE";
pub const DEFAULT_ALLOCATOR = std.heap.page_allocator;
pub const APP_NAME: []const u8 = "cmakepls";
pub const CONFIG_FILE_NAME = "config.json";
pub const VERSION_MAJOR = 0;
pub const VERSION_MINOR = 0;
pub const VERSION_PATCH = 1;
pub const TEMPLATE_DIR_NAME = "templates";
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
    place_compile_commands_in_cwd: bool,
};
pub const DEFAULT_CONFIG = ConfigFile{
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
    .place_compile_commands_in_cwd = true,
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
    return try std.fs.openDirAbsolute(appdata_str, .{});
}
pub fn make_appdata_dir(allocator: Allocator) !std.fs.Dir {
    const appdata_str = try std.fs.getAppDataDir(allocator, APP_NAME);
    defer allocator.free(appdata_str);
    try std.fs.makeDirAbsolute(appdata_str);
    return try open_appdata_dir(allocator);
}

/// user owns the returned data
pub fn read_config(allocator: Allocator) !ParsedConfig {
    const dir = try open_appdata_dir(allocator);
    const file = try dir.openFile(CONFIG_FILE_NAME, .{ .mode = .read_only });
    const buf = try file.readToEndAlloc(allocator, MAX_BYTES);
    defer allocator.free(buf);
    return try std.json.parseFromSlice(ConfigFile, allocator, buf, .{ .allocate = .alloc_always });
}
pub fn write_config(allocator: Allocator, config: ConfigFile) !void {
    var dir = open_appdata_dir(allocator) catch try make_appdata_dir(allocator);
    defer dir.close();
    const file = try dir.createFile(CONFIG_FILE_NAME, .{});
    defer file.close();
    try std.json.stringify(config, .{ .whitespace = .indent_4 }, file.writer());
}
pub fn get_config(allocator: Allocator) !ParsedConfig {
    const read: ?ParsedConfig = read_config(allocator) catch null;
    if (read) |conf| return conf;
    try write_config(allocator, DEFAULT_CONFIG);
    return try read_config(allocator);
}
pub fn get_template_dir(a: Allocator, name: cstring) !Dir {
    var appdata_dir = try get_appdata_dir(a);
    defer appdata_dir.close();
    var templates_dir = try appdata_dir.openDir("templates", .{});
    defer templates_dir.close();
    return try templates_dir.openDir(name, .{ .iterate = true });
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
