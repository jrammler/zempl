const std = @import("std");
const CodeGenerator = @import("codegen.zig").CodeGenerator;
const ZemplFile = @import("ast.zig").ZemplFile;

pub const FileEntry = struct {
    input_path: []const u8,
    output_path: []const u8,
    relative_path: []const u8,

    pub fn deinit(self: FileEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.input_path);
        allocator.free(self.output_path);
        allocator.free(self.relative_path);
    }
};

/// Scan a directory recursively for .zempl files
pub fn scanDirectory(allocator: std.mem.Allocator, input_dir: []const u8, output_dir: []const u8) ![]FileEntry {
    var files = std.ArrayList(FileEntry).empty;
    errdefer {
        for (files.items) |entry| {
            entry.deinit(allocator);
        }
        files.deinit(allocator);
    }

    var dir = try std.fs.cwd().openDir(input_dir, .{ .iterate = true });
    defer dir.close();

    try scanDirectoryRecursive(allocator, dir, input_dir, output_dir, "", &files);

    return try files.toOwnedSlice(allocator);
}

fn scanDirectoryRecursive(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    input_base: []const u8,
    output_base: []const u8,
    relative_prefix: []const u8,
    files: *std.ArrayList(FileEntry),
) !void {
    var it = dir.iterate();
    while (try it.next()) |entry| {
        const relative_path = if (relative_prefix.len == 0)
            try allocator.dupe(u8, entry.name)
        else
            try std.fs.path.join(allocator, &.{ relative_prefix, entry.name });

        switch (entry.kind) {
            .file => {
                if (std.mem.endsWith(u8, entry.name, ".zempl")) {
                    // Calculate output path (change .zempl to .zig)
                    const output_name = try std.mem.concat(allocator, u8, &.{
                        entry.name[0 .. entry.name.len - 6],
                        ".zig",
                    });
                    defer allocator.free(output_name);

                    const input_path = try std.fs.path.join(allocator, &.{ input_base, relative_path });
                    errdefer allocator.free(input_path);

                    const output_path = if (relative_prefix.len == 0)
                        try std.fs.path.join(allocator, &.{ output_base, output_name })
                    else
                        try std.fs.path.join(allocator, &.{ output_base, relative_prefix, output_name });
                    errdefer allocator.free(output_path);

                    try files.append(allocator, .{
                        .input_path = input_path,
                        .output_path = output_path,
                        .relative_path = relative_path,
                    });
                } else {
                    allocator.free(relative_path);
                }
            },
            .directory => {
                // Skip hidden directories
                if (entry.name[0] == '.') {
                    allocator.free(relative_path);
                    continue;
                }

                // Create output directory
                const output_subdir = try std.fs.path.join(allocator, &.{ output_base, relative_path });
                defer allocator.free(output_subdir);
                try std.fs.cwd().makePath(output_subdir);

                // Recurse into subdirectory
                var subdir = try dir.openDir(entry.name, .{ .iterate = true });
                defer subdir.close();

                try scanDirectoryRecursive(
                    allocator,
                    subdir,
                    input_base,
                    output_base,
                    relative_path,
                    files,
                );
                allocator.free(relative_path);
            },
            else => {
                allocator.free(relative_path);
            },
        }
    }
}

/// Process a single .zempl file
pub fn processFile(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    output_path: []const u8,
) !void {
    // Read input file
    const source = try std.fs.cwd().readFileAlloc(allocator, input_path, 1024 * 1024); // 1MB limit
    defer allocator.free(source);

    // Create output directory if needed
    const output_dir = std.fs.path.dirname(output_path) orelse ".";
    try std.fs.cwd().makePath(output_dir);

    // Open output file
    var output_file = try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();

    // Parse the zempl file
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;

    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);
    var lexer = Lexer.init(source_z, input_path);
    var parser = Parser.init(&lexer, allocator, input_path);

    const file = try parser.parseFile();
    defer file.deinit(allocator);

    // Generate code to buffer first, then write to file
    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    var codegen = CodeGenerator.init(allocator, &allocating.writer);
    try codegen.generateFile(file);

    // Write generated code to file
    const generated = allocating.written();
    try output_file.writeAll(generated);
}

/// Generate templates.zig index file
pub fn generateTemplatesZig(
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    files: []const FileEntry,
) !void {
    const templates_path = try std.fs.path.join(allocator, &.{ output_dir, "templates.zig" });
    defer allocator.free(templates_path);

    var templates_file = try std.fs.cwd().createFile(templates_path, .{});
    defer templates_file.close();

    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    // Write header comment
    try allocating.writer.writeAll("//! Auto-generated template index\n");
    try allocating.writer.writeAll("//! This file is generated by zempl - do not edit manually\n\n");

    // Write imports for all components
    for (files) |entry| {
        // Get module name from relative path
        const basename = std.fs.path.basename(entry.relative_path);
        const module_name = basename[0 .. basename.len - 6]; // Remove .zempl

        // Calculate import path relative to templates.zig
        const import_path = if (std.mem.indexOf(u8, entry.relative_path, "/") != null)
            entry.relative_path[0 .. entry.relative_path.len - 6] // Remove .zempl
        else
            module_name;

        try allocating.writer.print("pub const {s} = @import(\"{s}.zig\");\n", .{ module_name, import_path });
    }

    // Write to file
    try templates_file.writeAll(allocating.written());
}

// ============================================================================
// Tests
// ============================================================================

test "scanDirectory finds .zempl files" {
    const allocator = std.testing.allocator;

    // Create temporary test directory structure
    const test_dir = ".zig-cache/test_scan";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create test files
    try std.fs.cwd().writeFile(.{
        .sub_path = test_dir ++ "/test1.zempl",
        .data = "zempl Test1() {}",
    });
    try std.fs.cwd().writeFile(.{
        .sub_path = test_dir ++ "/test2.zempl",
        .data = "zempl Test2() {}",
    });
    try std.fs.cwd().writeFile(.{
        .sub_path = test_dir ++ "/not_zempl.txt",
        .data = "not a template",
    });

    // Create subdirectory
    try std.fs.cwd().makePath(test_dir ++ "/subdir");
    try std.fs.cwd().writeFile(.{
        .sub_path = test_dir ++ "/subdir/nested.zempl",
        .data = "zempl Nested() {}",
    });

    const files = try scanDirectory(allocator, test_dir, ".zig-cache/test_output");
    defer {
        for (files) |entry| {
            entry.deinit(allocator);
        }
        allocator.free(files);
    }

    try std.testing.expectEqual(@as(usize, 3), files.len);
}

test "processFile generates Zig output" {
    const allocator = std.testing.allocator;

    // Create test input
    const test_dir = ".zig-cache/test_process";
    const input_file = test_dir ++ "/input.zempl";
    const output_file = test_dir ++ "/output.zig";

    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().writeFile(.{
        .sub_path = input_file,
        .data = "zempl Hello() { <h1>Hello World</h1> }",
    });

    try processFile(allocator, input_file, output_file);

    // Verify output file was created
    const output = try std.fs.cwd().readFileAlloc(allocator, output_file, 1024);
    defer allocator.free(output);

    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "fn Hello"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "writer: @import(\"std\").Io.Writer"));
}
