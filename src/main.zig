const commands = @import("commands.zig");
const fs = @import("std").fs;
const common = @import("common.zig");
const DEFAULT_ALLOCATOR = common.DEFAULT_ALLOCATOR;
const Argv = common.Argv;

pub fn main() !void {
    var workspace = fs.cwd();
    defer workspace.close();
    var v = try Argv.init(DEFAULT_ALLOCATOR);
    defer v.deinit();
    if (v.keyword("version")) return try commands.version();
    if (v.keyword("global")) return try commands.global(DEFAULT_ALLOCATOR, v, workspace);
    if (v.keyword("template")) return try commands.template(DEFAULT_ALLOCATOR, v, workspace);
    if (v.keyword("project")) return try commands.project(DEFAULT_ALLOCATOR, v, workspace);
    if (v.keyword("generate")) return try commands.generate(DEFAULT_ALLOCATOR, v, workspace);
    if (v.keyword("build")) return try commands.build(DEFAULT_ALLOCATOR, v, workspace);
    if (v.keyword("run")) return try commands.run(DEFAULT_ALLOCATOR, v, workspace);
}
