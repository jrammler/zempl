const std = @import("std");

const Lexer = @import("zempl/lexer.zig").Lexer;
const Parser = @import("zempl/parser.zig").Parser;
const CodeGenerator = @import("zempl/codegen.zig").CodeGenerator;
const ZemplFile = @import("zempl/ast.zig").ZemplFile;

const Error = error{
    OutOfMemory,
    IoError,
    PathNotFound,
};

pub const USAGE =
    \\Usage: zempl <entry.zempl> <output dir>
    \\
    \\  Transforms a .zempl template file into a .zig source file.
    \\
    \\Arguments:
    \\  <entry.zempl>   Entry point template file
    \\  <output dir>    Path to output directory
    \\
    \\Options:
    \\  -h, --help    Show this help message
    \\
;

fn handleArg(arg: ?[]const u8) ?[]const u8 {
    if (arg) |a| {
        if (std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "--help")) {
            std.debug.print("{s}", .{USAGE});
            std.process.exit(0);
        }
        return a;
    }
    return null;
}

const QueueEntry = struct {
    src_path: []const u8,
    dst_path: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    defer args.deinit();

    _ = args.skip();

    const entry_path = handleArg(args.next()) orelse {
        std.debug.print("Error: Missing entry path\n\n{s}", .{USAGE});
        std.process.exit(1);
    };

    const output_path = handleArg(args.next()) orelse {
        std.debug.print("Error: Missing output directory\n\n{s}", .{USAGE});
        std.process.exit(1);
    };

    if (!std.mem.endsWith(u8, entry_path, ".zempl")) {
        std.debug.print("Error: Entry path must be a .zempl file\n", .{});
        std.process.exit(1);
    }

    var queue = std.ArrayList(QueueEntry).empty;
    defer {
        for (queue.items) |path| {
            allocator.free(path.src_path);
            allocator.free(path.dst_path);
        }
        queue.deinit(allocator);
    }

    _ = try enqueueRealpath(allocator, &queue, entry_path);

    const output_dir = std.fs.cwd().makeOpenPath(output_path, .{}) catch {
        std.debug.print("Error: Unable to create output directory\n", .{});
        std.process.exit(1);
    };

    var i: usize = 0;
    while (i < queue.items.len) : (i += 1) {
        const queued_file = queue.items[i];

        const source = std.fs.cwd().readFileAllocOptions(allocator, queued_file.src_path, 1024 * 1024, null, .fromByteUnits(1), 0) catch {
            std.debug.print("Error: Could not read file '{s}'\n", .{queued_file.src_path});
            std.process.exit(1);
        };
        defer allocator.free(source);

        var lexer = Lexer.init(source, queued_file.src_path);
        var parser = Parser.init(&lexer, allocator, queued_file.src_path);

        const file = parser.parseFile() catch |err| {
            std.debug.print("Error while parsing file '{s}': {}\n", .{ queued_file.src_path, err });
            if (parser.error_details) |ed| {
                std.debug.print("{f}\n", .{ed});
            }
            std.process.exit(1);
        };
        defer file.deinit(allocator);

        const curr_dir = std.fs.path.dirname(queued_file.src_path) orelse ".";

        for (file.items) |*decl| {
            switch (decl.*) {
                .import => |*import| {
                    const import_path_cwd = try std.fs.path.resolve(allocator, &.{ curr_dir, import.path });
                    defer allocator.free(import_path_cwd);

                    allocator.free(import.path);

                    import.path = try allocator.dupe(u8, try enqueueRealpath(allocator, &queue, import_path_cwd));
                },
                else => {},
            }
        }

        var out_file = output_dir.createFile(queued_file.dst_path, .{ .truncate = true }) catch {
            std.debug.print("Error: Could not create output file '{s}'\n", .{queued_file.dst_path});
            std.process.exit(1);
        };
        defer out_file.close();

        var buffer: [4096]u8 = undefined;
        var file_writer = out_file.writer(&buffer);
        const writer = &file_writer.interface;

        var codegen = CodeGenerator.init(writer);
        codegen.generateFile(file) catch {
            std.debug.print("Error while generating code for '{s}'\n", .{queued_file.dst_path});
            std.process.exit(1);
        };

        writer.flush() catch {
            std.debug.print("Error while writing file '{s}'\n", .{queued_file.dst_path});
            std.process.exit(1);
        };
    }
}

fn enqueueRealpath(allocator: std.mem.Allocator, queue: *std.ArrayList(QueueEntry), src_path: []const u8) ![]const u8 {
    const resolved_src_path = std.fs.cwd().realpathAlloc(allocator, src_path) catch {
        std.debug.print("Error: Could not resolve template path '{s}'\n", .{src_path});
        std.process.exit(1);
    };
    errdefer allocator.free(resolved_src_path);

    const dst_path = try std.fmt.allocPrint(allocator, "{}.zig", .{queue.items.len});
    errdefer allocator.free(dst_path);

    try queue.append(allocator, .{
        .src_path = resolved_src_path,
        .dst_path = dst_path,
    });
    return dst_path;
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
