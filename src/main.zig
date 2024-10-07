const cmds = @import("commands.zig");
const std = @import("std");
const fs = std.fs;
const io = std.io;
const cmm = @import("common.zig");
const pa = std.heap.page_allocator;

var argv: cmm.Argv = undefined;
var workspace: fs.Dir = undefined;

pub fn main() !void {
    argv = try cmm.Argv.init(pa);
    workspace = fs.cwd();
    defer workspace.close();
    defer argv.deinit();
    if (argv.keyword("init")) return try init();
    if (argv.keyword("set")) return try set();
    if (argv.keyword("version")) return try cmds.version();
    if (argv.keyword("generate")) return try cmds.generate(pa, argv, workspace);
    if (argv.keyword("build")) return try cmds.build(pa, argv, workspace);
    if (argv.keyword("run")) return try cmds.run(pa, argv, workspace);
    _ = try io.getStdErr().write("invalid argument list.");
}
pub inline fn init() !void {
    if (argv.keyword("project")) return try cmds.init_project(pa, argv, workspace);
    if (argv.keyword("template")) return try cmds.init_template(pa, argv, workspace);
}
pub inline fn set() !void {
    if (argv.keyword("config") and argv.keyword_slice(&[_][]const u8{ "-GLOBAL", "-G" })) {
        return try cmds.set_config_global(pa, argv);
    } else if (argv.keyword("config")) {
        return try cmds.set_config_local(pa, argv, workspace); // i should probably sync the template files as well
        // either search for the old string, but potentially cause issues when its ambiguous
        // or else just overwrite the files, but id need a safeguard to only overwrite the ones that need to be overwritten
    }
}
