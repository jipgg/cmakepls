const std = @import("std");
const utl = @import("utility.zig");
const mem = std.mem;
const fs = std.fs;
const json = std.json;
pub const CACHE_DIR: []const u8 = ".cmakepls_cache";
pub const LOCAL_DIR: []const u8 = ".cmakepls";
pub const KW_FORCED: []const u8 = "-FORCED";
pub const KW_VERBOSE: []const u8 = "-VERBOSE";
pub const APP_NAME: []const u8 = "cmakepls";
pub const CONFIG_FILE_NAME: []const u8 = "config.json";
pub const GLOBAL_FILE_NAME: []const u8 = "global.json";
pub const VERSION_MAJOR: u32 = 0;
pub const VERSION_MINOR: u32 = 1;
pub const VERSION_PATCH: u32 = 0;
pub const TEMPLATE_DIR_NAME: []const u8 = "templates";
pub const MAX_BYTES: usize = 1024 * 4;
pub const GlobalFile = struct { //wip
    toolchain_file: []const u8,
};
pub const ConfigFile = struct {
    cxx_standard: []const u8,
    cmake_minimum_required: []const u8,
    cxx_standard_required: []const u8,
    project_name: []const u8,
    build_dir: []const u8,
    source_dir: []const u8,
    bin_dir: []const u8,
    lib_dir: []const u8,
    place_compile_commands_in_workspace: []const u8,
};
pub const DEFAULT_CONFIG: ConfigFile = .{
    .project_name = "unnamed",
    .cmake_minimum_required = "3.22.2",
    .build_dir = "cmake-out",
    .cxx_standard = "17",
    .cxx_standard_required = "ON",
    .source_dir = "src",
    .bin_dir = "bin",
    .lib_dir = "lib",
    .place_compile_commands_in_workspace = "true",
};
pub const Argv = struct {
    allocator: mem.Allocator,
    data: [][:0]u8,
    pub fn init(allocator: mem.Allocator) !Argv {
        return Argv{ .allocator = allocator, .data = try std.process.argsAlloc(allocator) };
    }
    pub fn deinit(self: Argv) void {
        std.process.argsFree(self.allocator, self.data);
    }
    pub fn keyword(self: Argv, kw: []const u8) bool {
        for (self.data) |v| {
            if (std.mem.eql(u8, kw, v)) {
                return true;
            }
        }
        return false;
    }
    pub fn index_of(self: Argv, element: []const u8) ?usize {
        for (self.data, 0..) |v, i| {
            if (std.mem.eql(u8, element, v)) {
                return i;
            }
        }
        return null;
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
    pub fn param_slice(self: Argv, slice: []const []const u8) ?[]const u8 {
        for (slice) |keyw| {
            const arg = self.param(keyw);
            if (arg) |v| return v;
        }
        return null;
    }
    pub fn keyword_slice(self: Argv, slice: []const []const u8) bool {
        for (slice) |keyw| if (self.keyword(keyw)) {
            return true;
        };
        return false;
    }
};

pub fn present_default_config(allocator: mem.Allocator) !json.Parsed(ConfigFile) {
    var slice = std.ArrayList(u8).init(allocator);
    defer slice.deinit();
    try json.stringify(DEFAULT_CONFIG, .{ .whitespace = .indent_4 }, slice.writer());
    return try json.parseFromSlice(ConfigFile, allocator, slice.items, .{ .allocate = .alloc_always });
}
pub fn get_appdata_dir(allocator: mem.Allocator) !fs.Dir {
    return open_appdata_dir(allocator) catch try make_appdata_dir(allocator);
}

pub fn open_appdata_dir(allocator: mem.Allocator) !fs.Dir {
    const appdata_str = try fs.getAppDataDir(allocator, APP_NAME);
    defer allocator.free(appdata_str);
    return try fs.openDirAbsolute(appdata_str, .{ .no_follow = true });
}
pub fn make_appdata_dir(allocator: mem.Allocator) !fs.Dir {
    const appdata_str = try fs.getAppDataDir(allocator, APP_NAME);
    defer allocator.free(appdata_str);
    try fs.makeDirAbsolute(appdata_str);
    return try open_appdata_dir(allocator);
}
pub fn open_local_dir(workspace: fs.Dir) fs.Dir.OpenError!fs.Dir {
    return try workspace.openDir(LOCAL_DIR, .{ .no_follow = true });
}
pub fn make_local_dir(workspace: fs.Dir) !fs.Dir {
    try workspace.makeDir(LOCAL_DIR);
    return try workspace.openDir(LOCAL_DIR, .{ .no_follow = true });
}
pub fn has_local_dir(workspace: fs.Dir) bool {
    var exists: ?fs.Dir = open_local_dir(workspace) catch null;
    if (exists) |*v| {
        v.close();
        return true;
    } else return false;
}

pub fn read_config(allocator: mem.Allocator, dir: fs.Dir) !json.Parsed(ConfigFile) {
    const file = try dir.openFile(CONFIG_FILE_NAME, .{ .mode = .read_only });
    const buf = try file.readToEndAlloc(allocator, MAX_BYTES);
    defer allocator.free(buf);
    return try json.parseFromSlice(ConfigFile, allocator, buf, .{ .allocate = .alloc_always });
}
/// user owns the returned data
pub fn read_global_config(allocator: mem.Allocator) !json.Parsed(ConfigFile) {
    const dir = try open_appdata_dir(allocator);
    const file = try dir.openFile(CONFIG_FILE_NAME, .{ .mode = .read_only });
    const buf = try file.readToEndAlloc(allocator, MAX_BYTES);
    defer allocator.free(buf);
    return try json.parseFromSlice(ConfigFile, allocator, buf, .{ .allocate = .alloc_always });
}
pub fn write_config(dir: fs.Dir, config: ConfigFile) !void {
    const file = try dir.createFile(CONFIG_FILE_NAME, .{});
    defer file.close();
    try json.stringify(config, .{ .whitespace = .indent_4 }, file.writer());
}
pub fn write_global_config(allocator: mem.Allocator, config: ConfigFile) !void {
    var dir = open_appdata_dir(allocator) catch try make_appdata_dir(allocator);
    defer dir.close();
    const file = try dir.createFile(CONFIG_FILE_NAME, .{});
    defer file.close();
    try json.stringify(config, .{ .whitespace = .indent_4 }, file.writer());
}
pub fn write_local_config(workspace: fs.Dir, config_file: ConfigFile) !void {
    var dir = open_local_dir(workspace) catch try make_local_dir(workspace);
    defer dir.close();
    try write_config(dir, config_file);
}
pub fn get_config(allocator: mem.Allocator, workspace: fs.Dir) !json.Parsed(ConfigFile) {
    var parsed: ?json.Parsed(ConfigFile) = undefined;
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
pub fn get_template_dir(a: mem.Allocator, name: []const u8) !fs.Dir {
    var appdata_dir = try get_appdata_dir(a);
    defer appdata_dir.close();
    var templates_dir = try appdata_dir.openDir("templates", .{ .no_follow = true });
    defer templates_dir.close();
    return try templates_dir.openDir(name, .{ .iterate = true, .no_follow = true });
}
pub fn adjust_config_to_argv(c: *ConfigFile, argv: Argv) bool {
    var changed: bool = false;
    const field_names = comptime utl.field_names(ConfigFile);
    std.debug.print("doing shit\n", .{});
    inline for (field_names) |name| {
        const keyw: []const u8 = comptime "--" ++ name;
        std.debug.print("keyw: {s}\n", .{keyw});
        if (argv.keyword(keyw)) {
            if (argv.param(keyw)) |v| {
                std.debug.print("{s}:  {s} | {s}\n", .{ keyw, v, @field(c, name) });
                @field(c, name) = v;
                std.debug.print("v {s} | {s}\n", .{ v, @field(c, name) });
                changed = true;
            }
        }
    }
    return changed;
}
