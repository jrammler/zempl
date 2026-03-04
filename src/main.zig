const std = @import("std");
const files = @import("zempl/files.zig");

const USAGE =
    \\Usage: zempl <input-dir> <output-dir>
    \\
    \\  Transforms .zempl template files into .zig source files.
    \\
    \\Arguments:
    \\  <input-dir>   Directory containing .zempl files
    \\  <output-dir>  Directory where .zig files will be generated
    \\
    \\Options:
    \\  -h, --help    Show this help message
    \\
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("{s}", .{USAGE});
        std.process.exit(1);
    }

    // Check for help flag
    if (std.mem.eql(u8, args[1], "-h") or std.mem.eql(u8, args[1], "--help")) {
        std.debug.print("{s}", .{USAGE});
        std.process.exit(0);
    }

    if (args.len < 3) {
        std.debug.print("Error: Missing required arguments\n\n{s}", .{USAGE});
        std.process.exit(1);
    }

    const input_dir = args[1];
    const output_dir = args[2];

    // Validate input directory exists
    std.fs.cwd().access(input_dir, .{}) catch |err| {
        std.debug.print("Error: Cannot access input directory '{s}': {s}\n", .{
            input_dir,
            @errorName(err),
        });
        std.process.exit(1);
    };

    // Create output directory if it doesn't exist
    std.fs.cwd().makePath(output_dir) catch |err| {
        std.debug.print("Error: Cannot create output directory '{s}': {s}\n", .{
            output_dir,
            @errorName(err),
        });
        std.process.exit(1);
    };

    std.debug.print("Scanning '{s}' for .zempl files...\n", .{input_dir});

    // Scan for .zempl files
    const file_entries = files.scanDirectory(allocator, input_dir, output_dir) catch |err| {
        std.debug.print("Error scanning directory: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer {
        for (file_entries) |entry| {
            entry.deinit(allocator);
        }
        allocator.free(file_entries);
    }

    if (file_entries.len == 0) {
        std.debug.print("No .zempl files found in '{s}'\n", .{input_dir});
        std.process.exit(0);
    }

    std.debug.print("Found {d} .zempl file(s)\n\n", .{file_entries.len});

    // Process each file
    var success_count: usize = 0;
    var error_count: usize = 0;

    for (file_entries) |entry| {
        std.debug.print("Processing: {s} -> {s}\n", .{ entry.relative_path, entry.output_path });

        files.processFile(allocator, entry.input_path, entry.output_path) catch |err| {
            std.debug.print("  Error: {s}\n", .{@errorName(err)});
            error_count += 1;
            continue;
        };

        success_count += 1;
        std.debug.print("  ✓ Generated\n", .{});
    }

    std.debug.print("\n", .{});

    // Generate templates.zig index file
    if (success_count > 0) {
        std.debug.print("Generating templates.zig...\n", .{});
        files.generateTemplatesZig(allocator, output_dir, file_entries) catch |err| {
            std.debug.print("  Error generating templates.zig: {s}\n", .{@errorName(err)});
            error_count += 1;
        };
        if (error_count == 0) {
            std.debug.print("  ✓ Generated templates.zig\n", .{});
        }
    }

    // Print summary
    std.debug.print("\n{d} file(s) generated successfully\n", .{success_count});
    if (error_count > 0) {
        std.debug.print("{d} file(s) failed\n", .{error_count});
        std.process.exit(1);
    }
}

test "CLI argument parsing" {
    // Just verify the usage message exists
    try std.testing.expect(USAGE.len > 0);
}

// Reference all declarations in zempl module to ensure tests are compiled
// This is the standard Zig pattern for multi-file test discovery
test {
    std.testing.refAllDecls(@import("zempl/lexer.zig"));
    std.testing.refAllDecls(@import("zempl/parser.zig"));
    std.testing.refAllDecls(@import("zempl/ast.zig"));
    std.testing.refAllDecls(@import("zempl/zig_parse.zig"));
    std.testing.refAllDecls(@import("zempl/error.zig"));
    std.testing.refAllDecls(@import("zempl/codegen.zig"));
    std.testing.refAllDecls(@import("zempl/files.zig"));
}
