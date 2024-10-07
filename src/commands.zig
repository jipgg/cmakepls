const std = @import("std");
const cmm = @import("common.zig");
const utl = @import("utility.zig");
const mem = std.mem;
const fs = std.fs;
const KW_VERBOSE = cmm.KW_VERBOSE;
const KW_FORCED = cmm.KW_FORCED;
const CACHE_DIR = cmm.CACHE_DIR;
const CommandError = error{
    invalid_template_argument,
};

pub fn version() !void {
    utl.cout("version: {d}.{d}.{d}", .{ cmm.VERSION_MAJOR, cmm.VERSION_MINOR, cmm.VERSION_PATCH });
}

pub fn set_config_local(allocator: mem.Allocator, argv: cmm.Argv, workspace: fs.Dir) !void {
    var local_dir = cmm.open_local_dir(workspace) catch try cmm.make_local_dir(workspace);
    defer local_dir.close();
    var parsed_config = try cmm.read_config(allocator, local_dir);
    defer parsed_config.deinit();
    var conf = parsed_config.value;
    if (cmm.adjust_config_to_argv(&conf, argv)) {
        try cmm.write_local_config(workspace, conf);
    }
}
pub fn set_config_global(allocator: mem.Allocator, argv: cmm.Argv) !void {
    const parsed_config = try cmm.read_global_config(allocator);
    defer parsed_config.deinit();
    var conf = parsed_config.value;
    if (cmm.adjust_config_to_argv(&conf, argv)) {
        try cmm.write_global_config(allocator, conf);
    }
}
pub fn init_template(a: mem.Allocator, v: cmm.Argv, workspace: fs.Dir) !void {
    var appdata = cmm.open_appdata_dir(a) catch try cmm.make_appdata_dir(a);
    defer appdata.close();
    var templates_dir: fs.Dir = undefined;
    defer templates_dir.close();
    const opened_templates_dir: ?fs.Dir = appdata.openDir("templates", .{ .no_follow = true }) catch null;
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
    var files_it = mem.split(u8, files_arg, ",");
    while (files_it.next()) |entry| {
        if (entry[entry.len - 1] == '/') {
            try dir.makeDir(entry);
            try utl.deep_copy_dir(try workspace.openDir(entry, .{
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
    utl.cout("template written to {s}", .{try dir.realpath("", &out_buffer)});
}
pub fn generate(allocator: std.mem.Allocator, argv: cmm.Argv, workspace: std.fs.Dir) !void {
    utl.cout("[generating...]\n", .{});
    const parsed = try cmm.get_config(allocator, workspace);
    defer parsed.deinit();
    const conf = parsed.value;
    var cmd = std.ArrayList([]const u8).init(allocator);
    defer cmd.deinit();
    try cmd.append("cmake");
    try cmd.append("-B");
    try cmd.append(conf.build_dir);
    const bin_spec = "-DCMAKE_RUNTIME_OUTPUT_DIRECTORY=";
    const bin_dir = try mem.concat(allocator, u8, &[_][]const u8{ bin_spec, conf.bin_dir });
    defer allocator.free(bin_dir);
    try cmd.append(bin_dir);
    const lib_dir = try mem.concat(allocator, u8, &[_][]const u8{ "-DCMAKE_LIBRARY_OUTPUT_DIRECTORY=", conf.lib_dir });
    defer allocator.free(lib_dir);
    try cmd.append(lib_dir);
    const dll_dir = try mem.concat(allocator, u8, &[_][]const u8{ "-DCMAKE_ARCHIVE_OUTPUT_DIRECTORY=", conf.lib_dir });
    defer allocator.free(dll_dir);
    try cmd.append(dll_dir);
    utl.execute_command_slice(allocator, cmd.items, argv.keyword(KW_VERBOSE)) catch return;
    if (mem.eql(u8, conf.place_compile_commands_in_workspace, "true")) {
        try place_compile_commands_in_workspace(allocator, workspace, conf.build_dir, true);
    }
    utl.cout("project generated successfully.\n", .{});
}
pub fn build(a: std.mem.Allocator, v: cmm.Argv, workspace: std.fs.Dir) !void {
    utl.cout("[building...]\n", .{});
    const parsed = try cmm.get_config(a, workspace);
    defer parsed.deinit();
    const conf = parsed.value;
    try utl.execute_command_slice(a, &[_][]const u8{ "cmake", "--build", conf.build_dir }, v.keyword(KW_VERBOSE));
    utl.cout("project built successfully.\n", .{});
}
pub fn run(a: mem.Allocator, v: cmm.Argv, workspace: fs.Dir) !void {
    try build(a, v, workspace);
    utl.cout("[running...]\n", .{});
    const parsed = try cmm.get_config(a, workspace);
    defer parsed.deinit();
    const conf = parsed.value;
    const cmd = try mem.concat(a, u8, &[_][]const u8{ "./", conf.build_dir, "/", conf.bin_dir, "/", conf.project_name });
    defer a.free(cmd);
    try utl.execute_command_slice(a, &[_][]const u8{cmd}, true);
}

pub fn init_project(a: mem.Allocator, v: cmm.Argv, workspace: fs.Dir) !void {
    utl.cout("initializing project...\n", .{});
    if (v.param("project")) |t| {
        var config = try cmm.get_config(a, workspace);
        defer config.deinit();
        var conf = config.value;
        const changed = cmm.adjust_config_to_argv(&conf, v);
        var dir = try cmm.get_template_dir(a, t);
        defer dir.close();
        var buf = std.ArrayList(u8).init(a);
        defer buf.deinit();
        try process_entries(dir, workspace, &buf, conf);
        utl.cout("project initialized successfully.\n", .{});
        if (changed) try cmm.write_local_config(workspace, conf);
        return;
    }
    utl.cerr("failed to open", .{});
    return CommandError.invalid_template_argument;
}
//helpers
fn process_entries(src: fs.Dir, dest: fs.Dir, buf: *std.ArrayList(u8), conf: cmm.ConfigFile) !void {
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
inline fn process_file(dir: fs.Dir, entry: fs.Dir.Entry, workspace: fs.Dir, buf: *std.ArrayList(u8), conf: cmm.ConfigFile) !void {
    try dir.copyFile(entry.name, workspace, entry.name, .{});
    try buf.resize(cmm.MAX_BYTES);
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
inline fn process_line_substr(writer: anytype, str: []const u8, config: cmm.ConfigFile) !void {
    const v = str[1..str.len];
    const field_names = comptime utl.field_names(cmm.ConfigFile);
    inline for (field_names) |name| {
        if (mem.eql(u8, v, name)) {
            try writer.print("{s}", .{@field(config, name)});
            std.debug.print("{s}\n", .{@field(config, name)});
        }
    }
}
fn create_cache_and_generate(allocator: mem.Allocator, workspace: fs.Dir) !fs.Dir {
    const cmd = &[_][]const u8{ "cmake", "-G", "Ninja", "-B", CACHE_DIR, "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON" };
    try utl.execute_command_slice(allocator, cmd, false);
    return try workspace.openDir(CACHE_DIR, .{ .iterate = true, .no_follow = true });
}
fn place_compile_commands_in_workspace(allocator: mem.Allocator, workspace: fs.Dir, build_dir_str: []const u8, delete_cache_always: bool) !void {
    const compile_commands = "compile_commands.json";
    var build_dir: ?fs.Dir = workspace.openDir(build_dir_str, .{ .no_follow = true }) catch null;
    if (build_dir) |bd| {
        const file: ?fs.File = bd.openFile(compile_commands, .{}) catch null;
        if (file) |f| {
            f.close();
        } else {
            build_dir = null;
        }
    }
    var dir: fs.Dir = build_dir orelse try create_cache_and_generate(allocator, workspace);
    try dir.copyFile(compile_commands, workspace, compile_commands, .{});
    if (build_dir == null and delete_cache_always) {
        try utl.deep_clear_dir(dir);
        dir.close();
        try workspace.deleteDir(CACHE_DIR);
    } else dir.close();
}
