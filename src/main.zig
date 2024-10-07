const commands = @import("commands.zig");
const std = @import("std");
const fs = std.fs;
const io = std.io;
const common = @import("common.zig");
const DA = common.DEFAULT_ALLOCATOR;
const Argv = common.Argv;
const Dir = fs.Dir;

pub fn main() !void {
    var workspace = fs.cwd();
    defer workspace.close();
    var v = try Argv.init(DA);
    defer v.deinit();
    if (v.keyword("init")) return try init(v, workspace);
    if (v.keyword("set")) return try set(v, workspace);
    if (v.keyword("version")) return try commands.version();
    if (v.keyword("generate")) return try commands.generate(DA, v, workspace);
    if (v.keyword("build")) return try commands.build(DA, v, workspace);
    if (v.keyword("run")) return try commands.run(DA, v, workspace);
    _ = try io.getStdErr().write("invalid argument list.");
}
pub fn init(v: Argv, workspace: Dir) !void {
    if (v.keyword("project")) return try commands.init_project(DA, v, workspace);
    if (v.keyword("template")) return try commands.init_template(DA, v, workspace);
}
pub fn set(v: Argv, workspace: Dir) !void {
    if (v.keyword("global")) return try commands.set_global(DA, v, workspace);
}
