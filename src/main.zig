const commands = @import("commands.zig");
const common = @import("common.zig");
const DEFAULT_ALLOCATOR = common.DEFAULT_ALLOCATOR;
const Argv = common.Argv;

pub fn main() !void {
    var v = try Argv.init(DEFAULT_ALLOCATOR);
    defer v.deinit();
    if (v.keyword("global")) return try commands.global(DEFAULT_ALLOCATOR, v);
    if (v.keyword("init")) return try commands.init(DEFAULT_ALLOCATOR, v);
    if (v.keyword("template")) return try commands.template(DEFAULT_ALLOCATOR, v);
    if (v.keyword("project")) return try commands.project(DEFAULT_ALLOCATOR, v);
}
