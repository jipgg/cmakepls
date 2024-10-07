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
    var argv = try Argv.init(DA);
    defer argv.deinit();
    if (argv.keyword("init")) return try init(argv, workspace);
    if (argv.keyword("set")) return try set(argv, workspace);
    if (argv.keyword("version")) return try commands.version();
    if (argv.keyword("generate")) return try commands.generate(DA, argv, workspace);
    if (argv.keyword("build")) return try commands.build(DA, argv, workspace);
    if (argv.keyword("run")) return try commands.run(DA, argv, workspace);
    _ = try io.getStdErr().write("invalid argument list.");
}
pub fn init(argv: Argv, workspace: Dir) !void {
    if (argv.keyword("project")) return try commands.init_project(DA, argv, workspace);
    if (argv.keyword("template")) return try commands.init_template(DA, argv, workspace);
}
pub fn set(argv: Argv, workspace: Dir) !void {
    if (argv.keyword("global")) return try commands.set_global(DA, argv, workspace);
}
