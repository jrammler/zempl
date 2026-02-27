const std = @import("std");

/// Location in source code (file, line, column)
pub const Location = struct {
    file_path: []const u8,
    line: usize,
    column: usize,

    pub fn format(
        self: Location,
        writer: anytype,
    ) !void {
        try writer.print("{s}:{d}:{d}", .{ self.file_path, self.line, self.column });
    }
};

/// Base error type for all zempl errors
pub const ZemplError = error{
    SyntaxError,
    ZigParseError,
    HtmlParseError,
    IoError,
};

/// Detailed error information with context
pub const Error = struct {
    /// The type of error
    err_type: ZemplError,

    /// Where the error occurred
    location: Location,

    /// Human-readable error message
    message: []const u8,

    /// Source code snippet around the error (optional)
    context: ?[]const u8,

    /// Suggestion for fixing the error (optional)
    suggestion: ?[]const u8,

    pub fn init(
        err_type: ZemplError,
        location: Location,
        message: []const u8,
    ) Error {
        return .{
            .err_type = err_type,
            .location = location,
            .message = message,
            .context = null,
            .suggestion = null,
        };
    }

    pub fn withContext(self: Error, ctx: []const u8) Error {
        return .{
            .err_type = self.err_type,
            .location = self.location,
            .message = self.message,
            .context = ctx,
            .suggestion = self.suggestion,
        };
    }

    pub fn withSuggestion(self: Error, suggestion: []const u8) Error {
        return .{
            .err_type = self.err_type,
            .location = self.location,
            .message = self.message,
            .context = self.context,
            .suggestion = suggestion,
        };
    }

    pub fn format(
        self: Error,
        writer: anytype,
    ) !void {
        const err_name = switch (self.err_type) {
            ZemplError.SyntaxError => "syntax error",
            ZemplError.ZigParseError => "Zig parse error",
            ZemplError.HtmlParseError => "HTML parse error",
            ZemplError.IoError => "I/O error",
        };

        try writer.print("error: {s}\n", .{err_name});
        try writer.print("  ├─ {f}\n", .{self.location});
        try writer.print("  │\n", .{});
        try writer.print("  │ {s}\n", .{self.message});

        if (self.context) |ctx| {
            try writer.print("  │\n", .{});
            try writer.print("  │ {s}\n", .{ctx});
        }

        if (self.suggestion) |sugg| {
            try writer.print("  │\n", .{});
            try writer.print("  │ suggestion: {s}\n", .{sugg});
        }
    }

    /// Print error to stderr with nice formatting
    pub fn print(self: Error) void {
        std.debug.print("{f}", .{self});
    }
};

/// Error reporter that collects multiple errors
pub const ErrorReporter = struct {
    errors: std.ArrayList(Error),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ErrorReporter {
        return .{
            .errors = std.ArrayList(Error).empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ErrorReporter) void {
        self.errors.deinit(self.allocator);
    }

    pub fn report(self: *ErrorReporter, err: Error) !void {
        try self.errors.append(self.allocator, err);
    }

    pub fn hasErrors(self: ErrorReporter) bool {
        return self.errors.items.len > 0;
    }

    pub fn printAll(self: ErrorReporter) void {
        for (self.errors.items) |err| {
            err.print();
            std.debug.print("\n", .{});
        }
    }

    pub fn getErrorCount(self: ErrorReporter) usize {
        return self.errors.items.len;
    }
};

// Tests
test "Error initialization" {
    const loc = Location{
        .file_path = "test.zempl",
        .line = 10,
        .column = 5,
    };

    const err = Error.init(
        ZemplError.SyntaxError,
        loc,
        "unexpected token",
    );

    try std.testing.expectEqual(ZemplError.SyntaxError, err.err_type);
    try std.testing.expectEqualStrings("test.zempl", err.location.file_path);
    try std.testing.expectEqual(10, err.location.line);
    try std.testing.expectEqual(5, err.location.column);
    try std.testing.expectEqualStrings("unexpected token", err.message);
}

test "Error with context and suggestion" {
    const loc = Location{
        .file_path = "test.zempl",
        .line = 20,
        .column = 8,
    };

    var err = Error.init(
        ZemplError.ZigParseError,
        loc,
        "invalid syntax",
    );

    err = err.withContext("  @if (showHeader {");
    err = err.withSuggestion("add closing parenthesis");

    try std.testing.expect(err.context != null);
    try std.testing.expect(err.suggestion != null);
}

test "ErrorReporter" {
    const allocator = std.testing.allocator;
    var reporter = ErrorReporter.init(allocator);
    defer reporter.deinit();

    const err1 = Error.init(ZemplError.SyntaxError, .{
        .file_path = "file1.zempl",
        .line = 1,
        .column = 1,
    }, "error 1");
    const err2 = Error.init(ZemplError.IoError, .{
        .file_path = "file2.zempl",
        .line = 5,
        .column = 10,
    }, "error 2");

    try reporter.report(err1);
    try reporter.report(err2);

    try std.testing.expect(reporter.hasErrors());
    try std.testing.expectEqual(@as(usize, 2), reporter.getErrorCount());
}

test "Location formatting" {
    const loc = Location{
        .file_path = "test.zempl",
        .line = 42,
        .column = 5,
    };

    var buf: [100]u8 = undefined;
    const result = try std.fmt.bufPrint(&buf, "{f}", .{loc});
    try std.testing.expectEqualStrings("test.zempl:42:5", result);
}
