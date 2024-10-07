const std = @import("std");
const testing = std.testing;
const expect = testing.expect;
const common = @import("common.zig");
const ConfigFile = common.ConfigFile;
const meta = std.meta;
// Function to generate an array of compile-time field names
fn fieldNames(comptime T: type) []const []const u8 {
    const fields = std.meta.fields(T);
    var names: [fields.len][]const u8 = undefined;
    inline for (fields, 0..) |field, i| {
        names[i] = field.name;
    }
    return &names;
}

test "Reflection" {
    //std.debug.print("{s}\n", .{@field(common.DEFAULT_CONFIG, "project_name")});
    const names = fieldNames(ConfigFile);
    for (names) |name| {
        std.debug.print("{s}\n", .{name});
    }
    std.debug.print("names {s}\n", .{names[0]});
    //std.debug.print("{s}\n {d}", .{});
}
