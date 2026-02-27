const std = @import("std");

// Import zempl modules to include their tests
const zempl = @import("zempl.zig");

pub fn main() !void {}

test "empty test" {}

// Reference all declarations in zempl module to ensure tests are compiled
// This is the standard Zig pattern for multi-file test discovery
test {
    std.testing.refAllDecls(zempl);
}
