const std = @import("std");
const common = @import("common.zig");
const Allocator = std.mem.Allocator;
const Argv = common.Argv;
const Dir = std.fs.Dir;
const File = std.fs.File;
const process = std.process;
const mem = std.mem;
const string = []u8;
const cstring = []const u8;
const zstring = [:0]u8;
const czstring = [:0]const u8;
const stdout = std.io.getStdOut;
const KW_VERBOSE = common.KW_VERBOSE;
const KW_FORCED = common.KW_FORCED;

const format = std.fmt.format;
pub fn init(allocator: Allocator, v: Argv) !void {
    const parsed_conf = try common.get_config(allocator);
    defer parsed_conf.deinit();
    const conf = parsed_conf.value;
    const def = conf.defaults;
    var dir = std.fs.cwd();
    defer dir.close();
    const cmakelists = try dir.createFile("CMakeLists.txt", .{});
    var out = cmakelists.writer();
    const min_req_fmt = "cmake_minimum_required(VERSION {s})\n";
    try format(out, min_req_fmt, .{v.param("--version") orelse def.cmake_minimum_required});
    try format(out, "set(CMAKE_CXX_STANDARD {s})\n", .{v.param("--std") orelse def.cxx_standard});
    try format(out, "set(CMAKE_CXX_STANDARD_REQUIRED {s})\n", .{v.param("--std_required") orelse def.cxx_standard_required});
    const project_name = v.param("--name") orelse def.project;
    try format(out, "project({s})\n", .{project_name});
    try format(out, "file(GLOB SOURCE_DIR ${{CMAKE_SOURCE_DIR}}/{s}/*.cpp)\n", .{v.param("--source") orelse def.source_dir});
    try format(out, "add_executable({s} {s}${{SOURCE_DIR}})\n", .{ project_name, if (v.keyword("-WIN32")) "WIN32 " else "" });
    cmakelists.close();
    const cmakepresets = try dir.createFile("CMakePresets.json", .{});
    out = cmakepresets.writer();
    cmakepresets.close();
}
pub fn version() !void {
    try stdout().writer().print("version: {d}.{d}.{d}", .{ common.VERSION_MAJOR, common.VERSION_MINOR, common.VERSION_PATCH });
}
pub fn global(a: Allocator, v: Argv) !void {
    const parsed_config = common.read_config(a) catch try common.present_default_config(a);
    defer parsed_config.deinit();
    var conf = parsed_config.value;
    if (v.param("--toolchain")) |val| conf.toolchain = val;
    if (v.param("--defaults-project")) |val| conf.defaults.project = val;
    if (v.param("--defaults-cxx_standard")) |val| conf.defaults.cxx_standard = val;
    if (v.param("--defaults-cxx_standard_required")) |val| conf.defaults.cxx_standard_required = val;
    if (v.param("--defaults-build_dir")) |val| conf.defaults.build_dir = val;
    if (v.param("--defaults-export_compile_commands")) |val| conf.defaults.export_compile_commands = val;
    try common.write_config(a, conf);
}
pub fn template(a: Allocator, v: Argv) !void {
    var appdata = common.open_appdata_dir(a) catch try common.make_appdata_dir(a);
    defer appdata.close();
    var templates_dir: Dir = undefined;
    defer templates_dir.close();
    const opened_templates_dir: ?Dir = appdata.openDir("templates", .{}) catch null;
    if (opened_templates_dir == null) {
        try appdata.makeDir("templates");
        templates_dir = try appdata.openDir("templates", .{});
    } else templates_dir = opened_templates_dir.?;
    var cwd = std.fs.cwd();
    defer cwd.close();
    const name_arg = v.param("--name") orelse "unnamed_template";
    const files_arg = v.param("--files") orelse "";
    templates_dir.makeDir(name_arg) catch |err| {
        if (!v.keyword(KW_FORCED)) return err;
    };
    var dir = try templates_dir.openDir(name_arg, .{});
    defer dir.close();
    var files_it = std.mem.split(u8, files_arg, ",");
    while (files_it.next()) |file| try cwd.copyFile(file, dir, file, .{});
    var out_buffer: [100]u8 = undefined;
    try stdout().writer().print("template written to {s}", .{try dir.realpath("", &out_buffer)});
}
pub fn generate(a: Allocator, v: Argv) !void {
    const parsed = try common.get_config(a);
    defer parsed.deinit();
    const conf = parsed.value;
    var cmd = std.ArrayList([]const u8).init(a);
    defer cmd.deinit();
    try cmd.append("cmake");
    if (v.keyword("--toolchain") or !mem.eql(u8, conf.toolchain, "null")) {
        try cmd.append("--toolchain");
        try cmd.append(v.param("--toolchain") orelse conf.toolchain);
    }
    try cmd.append("-B");
    try cmd.append(conf.defaults.build_dir);
    const bin_spec = "-DCMAKE_RUNTIME_OUTPUT_DIRECTORY=";
    const bin_dir = try mem.concat(a, u8, &[_][]const u8{ bin_spec, conf.defaults.bin_dir });
    defer a.free(bin_dir);
    try cmd.append(bin_dir);
    const lib_dir = try mem.concat(a, u8, &[_][]const u8{ "-DCMAKE_LIBRARY_OUTPUT_DIRECTORY=", conf.defaults.lib_dir });
    defer a.free(lib_dir);
    try cmd.append(lib_dir);
    const dll_dir = try mem.concat(a, u8, &[_][]const u8{ "-DCMAKE_ARCHIVE_OUTPUT_DIRECTORY=", conf.defaults.lib_dir });
    defer a.free(dll_dir);
    try cmd.append(dll_dir);
    try common.execute_command_slice(a, cmd.items, v.keyword(KW_VERBOSE));
}
pub fn build(a: Allocator, v: Argv) !void {
    try generate(a, v);
    const parsed = try common.get_config(a);
    defer parsed.deinit();
    const conf = parsed.value;
    try common.execute_command_slice(a, &[_][]const u8{ "cmake", "--build", conf.defaults.build_dir }, v.keyword(KW_VERBOSE));
}
pub fn run(a: Allocator, v: Argv) !void {
    try build(a, v);
    const parsed = try common.get_config(a);
    defer parsed.deinit();
    const conf = parsed.value;
    const cmd = try mem.concat(a, u8, &[_][]const u8{ "./", conf.defaults.build_dir, "/", conf.defaults.bin_dir, "/", conf.defaults.project });
    defer a.free(cmd);
    try common.execute_command_str(a, cmd, true);
}

pub fn project(a: Allocator, v: Argv) !void {
    if (v.param("--template") orelse v.param("-t")) |t| {
        const config = try common.get_config(a);
        defer config.deinit();
        const conf = config.value;
        var dir = try common.get_template_dir(a, t);
        defer dir.close();
        var it = dir.iterate();
        var cwd = std.fs.cwd();
        defer cwd.close();
        var buf = std.ArrayList(u8).init(a);
        defer buf.deinit();
        while (try it.next()) |entry| {
            if (entry.kind != .file) continue;
            try dir.copyFile(entry.name, cwd, entry.name, .{});
            try buf.resize(common.MAX_BYTES);
            var file = try cwd.openFile(entry.name, .{ .mode = .read_write });
            try buf.resize(try file.readAll(buf.items));
            file.close();
            //try cwd.deleteFile(entry.name);
            file = try cwd.createFile(entry.name, .{});
            defer file.close();
            const file_writer = file.writer();
            var lines = mem.split(u8, buf.items, "\n");
            while (lines.next()) |line| {
                var line_it = mem.split(u8, line, "@");
                while (line_it.next()) |str| {
                    if (mem.count(u8, str, "!") > 0) {
                        try process_str(file_writer, str, conf);
                        continue;
                    }
                    try file_writer.print("{s}", .{str});
                }
                try file_writer.print("\n", .{});
            }
        }
    }
}
inline fn process_str(writer: anytype, str: []const u8, conf: common.ConfigFile) !void {
    const def = conf.defaults;
    if (mem.eql(u8, str, "!cmake_minimum_required")) {
        try writer.print("{s}", .{def.cmake_minimum_required});
        return;
    }
    if (mem.eql(u8, str, "!project")) {
        try writer.print("{s}", .{def.project});
        return;
    }
    if (mem.eql(u8, str, "!cxx_standard")) {
        try writer.print("{s}", .{def.cxx_standard});
        return;
    }
    if (mem.eql(u8, str, "!cxx_standard_required")) {
        try writer.print("{s}", .{def.cxx_standard_required});
        return;
    }
    if (mem.eql(u8, str, "!source_dir")) {
        try writer.print("{s}", .{def.source_dir});
        return;
    }
    if (mem.eql(u8, str, "!export_compile_commands")) {
        try writer.print("{s}", .{def.export_compile_commands});
        return;
    }
    if (mem.eql(u8, str, "!build_dir")) {
        try writer.print("{s}", .{def.build_dir});
        return;
    }
    std.debug.print("invalid keyword {s}\n", .{str});
}
