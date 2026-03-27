const std = @import("std");

pub fn escapeHtml(writer: *std.Io.Writer, value: anytype) !void {
    const value_type = @typeInfo(@TypeOf(value));
    switch (value_type) {
        .int => try writer.print("{}", .{value}),
        .pointer => |pointer| {
            if (pointer.size == .slice or pointer.size == .many) {
                if (pointer.child != u8)
                    @compileError("Unsupported type: " ++ value_type);
                try escapeHtmlString(writer, value);
            } else if (pointer.size == .one) {
                const child_info = @typeInfo(pointer.child);
                if (child_info != .array or child_info.array.child != u8)
                    @compileError("Unsupported type: " ++ value_type);
                try escapeHtmlString(writer, value);
            } else {
                @compileError("Unsupported type: " ++ value_type);
            }
        },
        else => @compileError("Unsupported type: " ++ value_type),
    }
}

pub fn escapeAttribute(writer: *std.Io.Writer, comptime name: []const u8, value: anytype) !void {
    const value_type = @typeInfo(@TypeOf(value));
    if (value_type == .bool and !value)
        return;
    try writer.writeAll(" ");
    try escapeHtmlString(writer, name);
    if (value_type == .bool)
        return;
    try writer.writeAll("=\"");
    try escapeHtml(writer, value);
    try writer.writeAll("\"");
}

fn escapeHtmlString(writer: *std.Io.Writer, value: []const u8) !void {
    for (value) |c| {
        switch (c) {
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            '&' => try writer.writeAll("&amp;"),
            '"' => try writer.writeAll("&quot;"),
            '\'' => try writer.writeAll("&#39;"),
            else => try writer.writeByte(c),
        }
    }
}
