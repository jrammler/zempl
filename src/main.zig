const std = @import("std");

const Lexer = @import("zempl/lexer.zig").Lexer;
const Parser = @import("zempl/parser.zig").Parser;
const CodeGenerator = @import("zempl/codegen.zig").CodeGenerator;

const Error = error{
    OutOfMemory,
    IoError,
};

const USAGE =
    \\Usage: zempl <input-dir> <output-dri>
    \\
    \\  Transforms .zempl template files into .zig source files.
    \\
    \\Arguments:
    \\  <input-dir>   Directory containing .zempl files
    \\  <output-dir>  Path to directory where .zig files will be generated
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    defer args.deinit();

    // skip program name
    _ = args.skip();

    const input_path = handleArg(args.next()) orelse {
        std.debug.print("Error: Missing input path\n\n{s}", .{USAGE});
        std.process.exit(1);
    };

    const output_path = handleArg(args.next()) orelse {
        std.debug.print("Error: Missing output path\n\n{s}", .{USAGE});
        std.process.exit(1);
    };

    // handle all args for help
    while (handleArg(args.next())) |_| {}

    const written_files = handleDir(allocator, input_path, output_path) catch {
        std.debug.print("Error: Error while processing template files\n", .{});
        std.process.exit(3);
    };
    std.debug.print("Generated {d} template files\n", .{written_files});
}

fn handleDir(allocator: std.mem.Allocator, input_path: []const u8, output_path: []const u8) Error!usize {
    var input_dir = std.fs.cwd().openDir(input_path, .{ .iterate = true }) catch {
        std.debug.print("Error: Could not open directory '{s}' for iteration\n", .{input_path});
        return error.IoError;
    };
    defer input_dir.close();

    std.fs.cwd().makePath(output_path) catch {
        std.debug.print("Error: Could not create directory '{s}'\n", .{output_path});
        return error.IoError;
    };

    var dir_content_writer: std.Io.Writer.Allocating = .init(allocator);
    defer dir_content_writer.deinit();

    var written: usize = 0;

    var it = input_dir.iterate();
    while (it.next() catch return error.IoError) |entry| {
        switch (entry.kind) {
            .directory => {
                const entry_input_path = try std.fs.path.join(allocator, &.{ input_path, entry.name });
                defer allocator.free(entry_input_path);

                const entry_output_path = try std.fs.path.join(allocator, &.{ output_path, entry.name });
                defer allocator.free(entry_output_path);

                const cnt = try handleDir(allocator, entry_input_path, entry_output_path);
                written += cnt;

                if (cnt > 0) {
                    dir_content_writer.writer.print("pub const {s} = @import(\"{s}/_templates.zig\");\n", .{ entry.name, entry.name }) catch return error.IoError;
                }
            },
            .file => {
                const ext = std.fs.path.extension(entry.name);
                if (!std.mem.eql(u8, ext, ".zempl")) continue;

                const template_name = entry.name[0 .. entry.name.len - ext.len];

                const entry_input_path = try std.fs.path.join(allocator, &.{ input_path, entry.name });
                defer allocator.free(entry_input_path);

                const out_name = try std.fmt.allocPrint(allocator, "{s}.zig", .{template_name});
                defer allocator.free(out_name);
                const entry_output_path = try std.fs.path.join(allocator, &.{ output_path, out_name });
                defer allocator.free(entry_output_path);

                const cnt = try handleFile(allocator, entry_input_path, entry_output_path);
                written += cnt;

                if (cnt > 0) {
                    dir_content_writer.writer.print("pub const {s} = @import(\"{s}\");\n", .{ template_name, out_name }) catch return error.IoError;
                }
            },
            else => {
                std.debug.print("Error: Skipping path '{s}'. Must be file or directory.\n", .{input_path});
            },
        }
    }

    if (written > 0) {
        const dir_content_path = try std.fs.path.join(allocator, &.{ output_path, "_templates.zig" });
        defer allocator.free(dir_content_path);
        const dir_content_file = std.fs.cwd().createFile(dir_content_path, .{}) catch return error.IoError;
        defer dir_content_file.close();
        dir_content_file.writeAll(dir_content_writer.written()) catch return error.IoError;
    }

    return written;
}

fn handleFile(allocator: std.mem.Allocator, input_path: []const u8, output_path: []const u8) Error!usize {
    const source = std.fs.cwd().readFileAllocOptions(allocator, input_path, 1024 * 1024, null, .fromByteUnits(1), 0) catch |err| {
        switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                std.debug.print("Error: Could not read file '{s}'\n", .{input_path});
                return error.IoError;
            },
        }
    };
    defer allocator.free(source);

    const output_dir = std.fs.path.dirname(output_path) orelse ".";
    std.fs.cwd().makePath(output_dir) catch {
        std.debug.print("Error: Could not create directory '{s}'\n", .{output_path});
        return error.IoError;
    };

    var lexer = Lexer.init(source, input_path);
    var parser = Parser.init(&lexer, allocator, input_path);

    const file = parser.parseFile() catch |err| {
        switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return 0,
        }
    };
    defer file.deinit(allocator);

    var output_file = std.fs.cwd().createFile(output_path, .{}) catch {
        std.debug.print("Error: Could not create file '{s}'\n", .{output_path});
        return error.IoError;
    };
    defer output_file.close();

    var buffer: [4096]u8 = undefined;
    var file_writer = output_file.writer(&buffer);
    const writer = &file_writer.interface;

    var codegen = CodeGenerator.init(writer);
    codegen.generateFile(file) catch {
        std.debug.print("Error: Error while writing file '{s}'\n", .{output_path});
        return error.IoError;
    };

    writer.flush() catch {
        std.debug.print("Error: Error while writing file '{s}'\n", .{output_path});
        return error.IoError;
    };

    return 1;
}

test {
    std.testing.refAllDecls(@import("zempl/ast.zig"));
    std.testing.refAllDecls(@import("zempl/codegen.zig"));
    std.testing.refAllDecls(@import("zempl/error.zig"));
    std.testing.refAllDecls(@import("zempl/lexer.zig"));
    std.testing.refAllDecls(@import("zempl/parser.zig"));
    std.testing.refAllDecls(@import("zempl/zig_parse.zig"));
}
