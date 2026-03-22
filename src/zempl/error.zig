const std = @import("std");
const Location = @import("lexer.zig").Location;

pub const ErrorDetails = struct {
    location: Location,
    message: []const u8,
    line: ?[]const u8,

    pub fn init(
        location: Location,
        message: []const u8,
        line: ?[]const u8,
    ) ErrorDetails {
        return .{
            .location = location,
            .message = message,
            .line = line,
        };
    }

    pub fn format(
        self: ErrorDetails,
        writer: anytype,
    ) !void {
        try writer.print("{f}:Error: {s}\n", .{ self.location, self.message });

        if (self.line) |line| {
            try writer.print("  │\n", .{});
            try writer.print("  │ {s}\n", .{line});
            try writer.print("  │ {s:>[]}\n", .{ "", self.location.column });
        }
    }

    /// Print error to stderr with nice formatting
    pub fn print(self: ErrorDetails) void {
        std.debug.print("{f}", .{self});
    }
};

test "Error initialization" {
    const loc = Location{
        .file_path = "test.zempl",
        .row = 10,
        .column = 5,
    };

    const err = ErrorDetails.init(
        loc,
        "unexpected token",
        null,
    );

    try std.testing.expectEqualStrings("test.zempl", err.location.file_path);
    try std.testing.expectEqual(10, err.location.row);
    try std.testing.expectEqual(5, err.location.column);
    try std.testing.expectEqualStrings("unexpected token", err.message);
}

test "Location formatting" {
    const loc = Location{
        .file_path = "test.zempl",
        .row = 42,
        .column = 5,
    };

    var buf: [100]u8 = undefined;
    const result = try std.fmt.bufPrint(&buf, "{f}", .{loc});
    try std.testing.expectEqualStrings("test.zempl:42:5", result);
}
