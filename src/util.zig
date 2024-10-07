const std = @import("std");
const meta = std.meta;
pub fn field_names(comptime T: type) []const []const u8 {
    const fields = comptime std.meta.fields(T);
    var names: [fields.len][]const u8 = undefined;
    inline for (fields, 0..) |field, i| {
        names[i] = field.name;
    }
    return &names;
}
