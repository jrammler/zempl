const std = @import("std");
const Location = @import("lexer.zig").Location;

pub const ErrorDetails = struct {
    location: Location,
    message: []const u8,
    line: []const u8,

    pub fn format(
        self: ErrorDetails,
        writer: anytype,
    ) !void {
        try writer.print("{f}:Error: {s}\n", .{ self.location, self.message });

        try writer.print("  │\n", .{});
        try writer.print("  │ {s}\n", .{self.line});
        const column = self.location.index - self.location.row_start + 1;
        try writer.print("  │ {[value]s:>[width]}\n", .{ .value = "^", .width = column });
    }
};

test "Location formatting" {
    const loc = Location{
        .file_path = "test.zempl",
        .row = 42,
        .row_start = 0,
        .index = 4,
    };

    var buf: [100]u8 = undefined;
    const result = try std.fmt.bufPrint(&buf, "{f}", .{loc});
    try std.testing.expectEqualStrings("test.zempl:42:5", result);
}

test "ErrorDetails format with caret" {
    const loc = Location{
        .file_path = "test.zempl",
        .row = 1,
        .row_start = 0,
        .index = 4,
    };

    const err = ErrorDetails{
        .location = loc,
        .message = "expected '}'",
        .line = "div {",
    };

    var buf: [100]u8 = undefined;
    const result = try std.fmt.bufPrint(&buf, "{f}", .{err});
    try std.testing.expectEqualStrings("test.zempl:1:5:Error: expected '}'\n  │\n  │ div {\n  │     ^\n", result);
}
