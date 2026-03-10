const std = @import("std");

const templates = @import("templates");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    var writer: std.Io.Writer.Allocating = .init(allocator);
    defer writer.deinit();

    try templates.example.Page(&writer.writer, "My Title");

    try std.testing.expectEqualStrings(
        \\<!DOCTYPE html><html><head><title>My Title</title></head><body><div class="card"><div class="card-header"><h1 class="heading">Welcome</h1></div><div class="card-body"><p>Welcome!</p></div></div><ul><li>apple</li><li>banana</li><li>cherry</li></ul><div class="countdown"><span>3</span><span>2</span><span>1</span><span>Done!</span></div><a href="/profile/42">Click here</a></body></html>
    , writer.written());
}
