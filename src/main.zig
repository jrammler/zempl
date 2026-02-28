const std = @import("std");

pub fn main() !void {}

test "empty test" {}

// Reference all declarations in zempl module to ensure tests are compiled
// This is the standard Zig pattern for multi-file test discovery
test {
    std.testing.refAllDecls(@import("zempl/lexer.zig"));
    std.testing.refAllDecls(@import("zempl/parser.zig"));
    std.testing.refAllDecls(@import("zempl/ast.zig"));
    std.testing.refAllDecls(@import("zempl/zig_parse.zig"));
    std.testing.refAllDecls(@import("zempl/error.zig"));
}
