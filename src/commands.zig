const std = @import("std");
const common = @import("common.zig");
const util = @import("util.zig");
const Allocator = std.mem.Allocator;
const Argv = common.Argv;
const Dir = std.fs.Dir;
const File = std.fs.File;
const ConfigFile = common.ConfigFile;
const process = std.process;
const mem = std.mem;
const KW_VERBOSE = common.KW_VERBOSE;
const KW_FORCED = common.KW_FORCED;
const CACHE_DIR = common.CACHE_DIR;
const CommandError = error{
    invalid_template_argument,
};

pub fn version() !void {
    try stdout("version: {d}.{d}.{d}", .{ common.VERSION_MAJOR, common.VERSION_MINOR, common.VERSION_PATCH });
}
pub fn set_global(a: Allocator, v: Argv, workspace: Dir) !void {
    const parsed_config = try common.get_config(a, workspace);
    defer parsed_config.deinit();
    var conf = parsed_config.value;
    if (common.adjust_config_to_argv(&conf, v)) {
        try common.write_global_config(a, conf);
    }
}
pub fn init_template(a: Allocator, v: Argv, workspace: Dir) !void {
    var appdata = common.open_appdata_dir(a) catch try common.make_appdata_dir(a);
    defer appdata.close();
    var templates_dir: Dir = undefined;
    defer templates_dir.close();
    const opened_templates_dir: ?Dir = appdata.openDir("templates", .{ .no_follow = true }) catch null;
    if (opened_templates_dir == null) {
        try appdata.makeDir("templates");
        templates_dir = try appdata.openDir("templates", .{ .no_follow = true });
    } else templates_dir = opened_templates_dir.?;
    const name_arg = v.param("--name") orelse "unnamed_template";
    const files_arg = v.param("--files") orelse "";
    templates_dir.makeDir(name_arg) catch |err| {
        if (!v.keyword(KW_FORCED)) return err;
    };
    var dir = try templates_dir.openDir(name_arg, .{ .no_follow = true });
    defer dir.close();
    var files_it = std.mem.split(u8, files_arg, ",");
    while (files_it.next()) |entry| {
        if (entry[entry.len - 1] == '/') {
            try dir.makeDir(entry);
            try common.copy_dir_recursively(try workspace.openDir(entry, .{
                .iterate = true,
                .no_follow = true,
            }), try dir.openDir(entry, .{
                .iterate = true,
                .no_follow = true,
            }));
            continue;
        }
        try workspace.copyFile(entry, dir, entry, .{});
    }
    var out_buffer: [100]u8 = undefined;
    try stdout("template written to {s}", .{try dir.realpath("", &out_buffer)});
}
pub fn generate(a: Allocator, v: Argv, workspace: Dir) !void {
    try stdout("[generating...]\n", .{});
    const parsed = try common.get_config(a, workspace);
    defer parsed.deinit();
    var conf = parsed.value;
    if (!common.adjust_config_to_argv(&conf, v)) {
        try stderr("What the fuck mate.\n", .{});
    } else {
        try stderr("Kinda fucked mate.\n", .{});
    }
    var cmd = std.ArrayList([]const u8).init(a);
    defer cmd.deinit();
    try cmd.append("cmake");
    // if (v.keyword("--toolchain") or !mem.eql(u8, conf.toolchain, "null")) {
    //     try cmd.append("--toolchain");
    //     try cmd.append(v.param("--toolchain") orelse conf.toolchain);
    // }
    try cmd.append("-B");
    try cmd.append(conf.build_dir);
    const bin_spec = "-DCMAKE_RUNTIME_OUTPUT_DIRECTORY=";
    const bin_dir = try mem.concat(a, u8, &[_][]const u8{ bin_spec, conf.bin_dir });
    defer a.free(bin_dir);
    try cmd.append(bin_dir);
    const lib_dir = try mem.concat(a, u8, &[_][]const u8{ "-DCMAKE_LIBRARY_OUTPUT_DIRECTORY=", conf.lib_dir });
    defer a.free(lib_dir);
    try cmd.append(lib_dir);
    const dll_dir = try mem.concat(a, u8, &[_][]const u8{ "-DCMAKE_ARCHIVE_OUTPUT_DIRECTORY=", conf.lib_dir });
    defer a.free(dll_dir);
    try cmd.append(dll_dir);
    try common.execute_command_slice(a, cmd.items, v.keyword(KW_VERBOSE));
    if (mem.eql(u8, conf.place_compile_commands_in_workspace, "true")) {
        try place_compile_commands_in_workspace(a, workspace, conf.build_dir, true);
    }
    try stdout("project generated successfully.\n", .{});
}
pub fn build(a: Allocator, v: Argv, workspace: Dir) !void {
    try stdout("[building...]\n", .{});
    const parsed = try common.get_config(a, workspace);
    defer parsed.deinit();
    const conf = parsed.value;
    try common.execute_command_slice(a, &[_][]const u8{ "cmake", "--build", conf.build_dir }, v.keyword(KW_VERBOSE));
    try stdout("project built successfully.\n", .{});
}
pub fn run(a: Allocator, v: Argv, workspace: Dir) !void {
    try build(a, v, workspace);
    try stdout("[running...]\n", .{});
    const parsed = try common.get_config(a, workspace);
    defer parsed.deinit();
    const conf = parsed.value;
    const cmd = try mem.concat(a, u8, &[_][]const u8{ "./", conf.build_dir, "/", conf.bin_dir, "/", conf.project_name });
    defer a.free(cmd);
    try common.execute_command_slice(a, &[_][]const u8{cmd}, true);
}

pub fn init_project(a: Allocator, v: Argv, workspace: Dir) !void {
    try stdout("initializing project...\n", .{});
    if (v.param("project")) |t| {
        var config = try common.get_config(a, workspace);
        defer config.deinit();
        var conf = config.value;
        const changed = common.adjust_config_to_argv(&conf, v);
        var dir = try common.get_template_dir(a, t);
        defer dir.close();
        var buf = std.ArrayList(u8).init(a);
        defer buf.deinit();
        try process_entries(dir, workspace, &buf, conf);
        try stdout("project initialized successfully.\n", .{});
        if (changed) try write_local_config(workspace, conf);
        return;
    }
    try stderr("failed to open", .{});
    return CommandError.invalid_template_argument;
}
//helpers
fn process_entries(src: Dir, dest: Dir, buf: *std.ArrayList(u8), conf: ConfigFile) !void {
    var it = src.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .file) {
            try process_file(src, entry, dest, buf, conf);
            continue;
        }
        if (entry.kind == .directory) {
            try dest.makeDir(entry.name);
            var dest_subdir = try dest.openDir(entry.name, .{ .iterate = true, .no_follow = true });
            defer dest_subdir.close();
            var src_subdir = try src.openDir(entry.name, .{ .iterate = true, .no_follow = true });
            defer src_subdir.close();
            try process_entries(src_subdir, dest_subdir, buf, conf);
            continue;
        }
    }
}
inline fn process_file(dir: Dir, entry: Dir.Entry, workspace: Dir, buf: *std.ArrayList(u8), conf: ConfigFile) !void {
    try dir.copyFile(entry.name, workspace, entry.name, .{});
    try buf.resize(common.MAX_BYTES);
    var file = try workspace.openFile(entry.name, .{ .mode = .read_write });
    try buf.resize(try file.readAll(buf.items));
    file.close();
    //try cwd.deleteFile(entry.name);
    file = try workspace.createFile(entry.name, .{});
    defer file.close();
    const file_writer = file.writer();
    var lines = mem.split(u8, buf.items, "\n");
    while (lines.next()) |line| {
        var line_it = mem.split(u8, line, "@");
        while (line_it.next()) |str| {
            if (mem.count(u8, str, "!") > 0) {
                try process_line_substr(file_writer, str, conf);
                continue;
            }
            try file_writer.print("{s}", .{str});
        }
        try file_writer.print("\n", .{});
    }
}
inline fn process_line_substr(writer: anytype, str: []const u8, c: ConfigFile) !void {
    const v = str[1..str.len];
    const field_names = comptime util.field_names(ConfigFile);
    inline for (field_names) |name| {
        if (mem.eql(u8, v, name)) {
            try writer.print("{s}", .{@field(c, name)});
            std.debug.print("{s}\n", .{@field(c, name)});
        }
    }
}
fn create_cache_and_generate(allocator: Allocator, workspace: Dir) !Dir {
    const cmd = &[_][]const u8{ "cmake", "-G", "Ninja", "-B", CACHE_DIR, "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON" };
    try common.execute_command_slice(allocator, cmd, false);
    return try workspace.openDir(CACHE_DIR, .{ .iterate = true, .no_follow = true });
}
fn place_compile_commands_in_workspace(allocator: Allocator, workspace: Dir, build_dir_str: []const u8, delete_cache_always: bool) !void {
    const compile_commands = "compile_commands.json";
    var build_dir: ?Dir = workspace.openDir(build_dir_str, .{ .no_follow = true }) catch null;
    if (build_dir) |bd| {
        const file: ?File = bd.openFile(compile_commands, .{}) catch null;
        if (file) |f| {
            f.close();
        } else {
            build_dir = null;
        }
    }
    var dir: Dir = build_dir orelse try create_cache_and_generate(allocator, workspace);
    try dir.copyFile(compile_commands, workspace, compile_commands, .{});
    if (build_dir == null and delete_cache_always) {
        try common.delete_dir_contents(dir);
        dir.close();
        try workspace.deleteDir(CACHE_DIR);
    } else dir.close();
}
inline fn stdout(comptime format: []const u8, args: anytype) !void {
    try std.io.getStdOut().writer().print(comptime format, args);
}
inline fn stderr(comptime format: []const u8, args: anytype) !void {
    try std.io.getStdErr().writer().print(comptime format, args);
}
fn write_local_config(workspace: Dir, config_file: ConfigFile) !void {
    var dir = common.open_local_dir(workspace) catch try common.make_local_dir(workspace);
    defer dir.close();
    try common.write_config(dir, config_file);
}
