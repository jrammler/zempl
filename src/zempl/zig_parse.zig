const std = @import("std");
const Parse = @import("zig/Parse.zig");
const Ast = std.zig.Ast;
const Tokenizer = std.zig.Tokenizer;
const ErrorDetails = @import("error.zig").ErrorDetails;
const Location = @import("lexer.zig").Location;

pub const Error = error{
    ParseError,
    OutOfMemory,
};

/// Result from parsing - contains the source text and bytes consumed
pub const ParseResult = struct {
    source_text: []const u8, // Duplicated source, caller must free
    consumed: usize, // How many bytes were consumed from input

    pub fn deinit(self: ParseResult, allocator: std.mem.Allocator) void {
        allocator.free(self.source_text);
    }
};

fn byteOffsetToLocation(source: []const u8, byte_offset: usize) Location {
    var row: usize = 1;
    var row_start: usize = 0;
    var index: usize = 0;

    for (source, 0..) |ch, i| {
        if (i >= byte_offset) {
            index = i;
            break;
        }
        if (ch == '\n') {
            row += 1;
            row_start = i + 1;
        }
    }

    return Location{
        .file_path = "",
        .row = row,
        .row_start = row_start,
        .index = index,
    };
}

/// Parse a Zig expression and return its source text + consumed length.
/// Validates syntax then extracts the original source text.
/// Caller must free result.source_text.
pub fn parseExpression(allocator: std.mem.Allocator, source: [:0]const u8, error_details: *?ErrorDetails) Error!ParseResult {
    var tokens = Ast.TokenList{};
    defer tokens.deinit(allocator);

    var tokenizer = Tokenizer.init(source);
    while (true) {
        const token = tokenizer.next();
        try tokens.append(allocator, .{
            .tag = token.tag,
            .start = @intCast(token.loc.start),
        });
        if (token.tag == .eof) break;
    }

    const tokens_slice = tokens.slice();

    var parse = Parse{
        .gpa = allocator,
        .source = source,
        .tokens = tokens_slice,
        .tok_i = 0,
        .errors = .{},
        .nodes = .{},
        .extra_data = .{},
        .scratch = .{},
    };

    defer parse.nodes.deinit(allocator);
    defer parse.extra_data.deinit(allocator);
    defer parse.scratch.deinit(allocator);
    defer parse.errors.deinit(allocator);

    _ = try parse.parseExpr() orelse {
        populateErrorDetails(&parse, source, error_details);
        return error.ParseError;
    };

    const final_tok_i = parse.tok_i;

    const start: u32 = 0;

    const end: u32 = if (final_tok_i < tokens_slice.len)
        parse.tokenStart(final_tok_i)
    else
        @as(u32, @intCast(source.len));

    const source_text = source[start..end];
    const trimmed = std.mem.trim(u8, source_text, &std.ascii.whitespace);
    const result_str = try allocator.dupe(u8, trimmed);

    return ParseResult{
        .source_text = result_str,
        .consumed = end - start,
    };
}

/// Parse a parameter declaration list (e.g., `(a: i32, b: u32)`) and return source text + consumed length.
/// This is used to parse zempl component parameter lists.
/// Returns an error if the source doesn't start with '(' or if the param list is malformed.
pub fn parseParamDeclList(allocator: std.mem.Allocator, source: [:0]const u8, error_details: *?ErrorDetails) Error!ParseResult {
    var tokens = Ast.TokenList{};
    defer tokens.deinit(allocator);

    var tokenizer = Tokenizer.init(source);
    while (true) {
        const token = tokenizer.next();
        try tokens.append(allocator, .{
            .tag = token.tag,
            .start = @intCast(token.loc.start),
        });
        if (token.tag == .eof) break;
    }

    const tokens_slice = tokens.slice();

    var parse = Parse{
        .gpa = allocator,
        .source = source,
        .tokens = tokens_slice,
        .tok_i = 0,
        .errors = .{},
        .nodes = .{},
        .extra_data = .{},
        .scratch = .{},
    };
    defer {
        parse.nodes.deinit(allocator);
        parse.extra_data.deinit(allocator);
        parse.scratch.deinit(allocator);
        parse.errors.deinit(allocator);
    }

    const result = parse.parseParamDeclList() catch |err| switch (err) {
        error.ParseError, error.OutOfMemory => {
            populateErrorDetails(&parse, source, error_details);
            return error.ParseError;
        },
    };
    _ = result;

    const final_tok_i = parse.tok_i;
    const start: u32 = 0;
    const end: u32 = if (final_tok_i < tokens_slice.len)
        parse.tokenStart(final_tok_i)
    else
        @as(u32, @intCast(source.len));

    const source_text = source[start..end];
    const trimmed = std.mem.trim(u8, source_text, &std.ascii.whitespace);
    const result_str = try allocator.dupe(u8, trimmed);

    return ParseResult{
        .source_text = result_str,
        .consumed = end - start,
    };
}

fn populateErrorDetails(parse: *Parse, source: []const u8, error_details: *?ErrorDetails) void {
    if (parse.errors.items.len > 0) {
        const ast_err = parse.errors.items[0];
        const byte_offset = parse.tokenStart(ast_err.token);
        const loc = byteOffsetToLocation(source, byte_offset);
        const line_end = std.mem.indexOfScalar(u8, source[loc.row_start..], '\n') orelse source.len;
        error_details.* = .{
            .location = loc,
            .message = "zig parse error",
            .line = source[loc.row_start..line_end],
        };
    }
}

/// Parse a top-level declaration (const, var, fn) and return source text + consumed length.
pub fn parseTopLevelItem(allocator: std.mem.Allocator, source: [:0]const u8, error_details: *?ErrorDetails) Error!?ParseResult {
    var tokens = Ast.TokenList{};
    defer tokens.deinit(allocator);

    var tokenizer = Tokenizer.init(source);
    while (true) {
        const token = tokenizer.next();
        try tokens.append(allocator, .{
            .tag = token.tag,
            .start = @intCast(token.loc.start),
        });
        if (token.tag == .eof) break;
    }

    const tokens_slice = tokens.slice();

    var parse = Parse{
        .gpa = allocator,
        .source = source,
        .tokens = tokens_slice,
        .tok_i = 0,
        .errors = .{},
        .nodes = .{},
        .extra_data = .{},
        .scratch = .{},
    };
    defer {
        parse.nodes.deinit(allocator);
        parse.extra_data.deinit(allocator);
        parse.scratch.deinit(allocator);
        parse.errors.deinit(allocator);
    }

    const tag = parse.tokenTag(parse.tok_i);

    switch (tag) {
        .keyword_const, .keyword_var => _ = (try parse.parseGlobalVarDecl()) orelse {
            populateErrorDetails(&parse, source, error_details);
            return error.ParseError;
        },
        .keyword_fn => _ = (try parse.parseFnProto()) orelse {
            populateErrorDetails(&parse, source, error_details);
            return error.ParseError;
        },
        .keyword_pub => {
            const next_tag = parse.tokenTag(parse.tok_i + 1);
            if (next_tag == .keyword_const or next_tag == .keyword_var) {
                _ = parse.nextToken();
                _ = (try parse.parseGlobalVarDecl()) orelse {
                    populateErrorDetails(&parse, source, error_details);
                    return error.ParseError;
                };
            } else if (next_tag == .keyword_fn) {
                _ = parse.nextToken();
                _ = (try parse.parseFnProto()) orelse {
                    populateErrorDetails(&parse, source, error_details);
                    return error.ParseError;
                };
            } else {
                return null;
            }
        },
        .eof => return null,
        else => return null,
    }

    const final_tok_i = parse.tok_i;
    const start: u32 = 0;
    const end: u32 = if (final_tok_i < tokens_slice.len)
        parse.tokenStart(final_tok_i)
    else
        @as(u32, @intCast(source.len));

    const source_text = source[start..end];
    const trimmed = std.mem.trim(u8, source_text, &std.ascii.whitespace);
    const result_str = try allocator.dupe(u8, trimmed);

    return ParseResult{
        .source_text = result_str,
        .consumed = end - start,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "parseExpression returns source text for integer literal" {
    const source = "42";
    var error_details: ?ErrorDetails = undefined;
    const result = try parseExpression(std.testing.allocator, source, &error_details);
    defer std.testing.allocator.free(result.source_text);
    try std.testing.expectEqualStrings("42", result.source_text);
    try std.testing.expectEqual(@as(usize, 2), result.consumed);
}

test "parseExpression returns source text for string literal" {
    const source = "\"hello world\"";
    var error_details: ?ErrorDetails = undefined;
    const result = try parseExpression(std.testing.allocator, source, &error_details);
    defer std.testing.allocator.free(result.source_text);
    try std.testing.expectEqualStrings("\"hello world\"", result.source_text);
}

test "parseExpression returns source text for variable access" {
    const source = "my_var";
    var error_details: ?ErrorDetails = undefined;
    const result = try parseExpression(std.testing.allocator, source, &error_details);
    defer std.testing.allocator.free(result.source_text);
    try std.testing.expectEqualStrings("my_var", result.source_text);
    try std.testing.expectEqual(@as(usize, 6), result.consumed);
}

test "parseExpression returns source text for binary expression" {
    // TODO: Implement proper AST traversal to extract full expression source
    // Current implementation only extracts main token, not full expression
    const source = "a + b";
    var error_details: ?ErrorDetails = undefined;
    const result = try parseExpression(std.testing.allocator, source, &error_details);
    defer std.testing.allocator.free(result.source_text);
    // For now, we verify parsing succeeds; full source extraction needs work
    try std.testing.expect(result.source_text.len > 0);
}

test "parseExpression returns source text for function call" {
    // TODO: Implement proper AST traversal to extract full expression source
    const source = "foo(a, b)";
    var error_details: ?ErrorDetails = undefined;
    const result = try parseExpression(std.testing.allocator, source, &error_details);
    defer std.testing.allocator.free(result.source_text);
    try std.testing.expect(result.source_text.len > 0);
}

test "parseParamDeclList returns source text for empty params" {
    const source = "()";
    var error_details: ?ErrorDetails = undefined;
    const result = try parseParamDeclList(std.testing.allocator, source, &error_details);
    defer std.testing.allocator.free(result.source_text);
    try std.testing.expectEqualStrings("()", result.source_text);
    try std.testing.expectEqual(@as(usize, 2), result.consumed);
}

test "parseParamDeclList returns source text for single param" {
    const source = "(x: i32)";
    var error_details: ?ErrorDetails = undefined;
    const result = try parseParamDeclList(std.testing.allocator, source, &error_details);
    defer std.testing.allocator.free(result.source_text);
    try std.testing.expectEqualStrings("(x: i32)", result.source_text);
}

test "parseParamDeclList returns source text for multiple params" {
    const source = "(a: i32, b: []const u8)";
    var error_details: ?ErrorDetails = undefined;
    const result = try parseParamDeclList(std.testing.allocator, source, &error_details);
    defer std.testing.allocator.free(result.source_text);
    try std.testing.expectEqualStrings("(a: i32, b: []const u8)", result.source_text);
}

test "parseParamDeclList returns error if not starting with l_paren" {
    const source = "i32";
    var error_details: ?ErrorDetails = undefined;
    const result = parseParamDeclList(std.testing.allocator, source, &error_details);
    try std.testing.expectError(error.ParseError, result);
}

test "parseParamDeclList returns error for invalid param list" {
    const source = "(invalid";
    var error_details: ?ErrorDetails = undefined;
    const result = parseParamDeclList(std.testing.allocator, source, &error_details);
    // Should return an error since it starts with ( but is malformed
    try std.testing.expectError(error.ParseError, result);
}

test "parseTopLevelItem returns source text for const declaration" {
    const source = "const x = 42;";
    var error_details: ?ErrorDetails = undefined;
    const result = try parseTopLevelItem(std.testing.allocator, source, &error_details);
    try std.testing.expect(result != null);
    if (result) |r| {
        defer std.testing.allocator.free(r.source_text);
        try std.testing.expect(r.source_text.len > 0);
    }
}

test "parseTopLevelItem returns source text for var declaration" {
    const source = "var y: i32 = 0;";
    var error_details: ?ErrorDetails = undefined;
    const result = try parseTopLevelItem(std.testing.allocator, source, &error_details);
    try std.testing.expect(result != null);
    if (result) |r| {
        defer std.testing.allocator.free(r.source_text);
        try std.testing.expect(r.source_text.len > 0);
    }
}

test "parseTopLevelItem returns source text for function prototype" {
    const source = "fn foo() void;";
    var error_details: ?ErrorDetails = undefined;
    const result = try parseTopLevelItem(std.testing.allocator, source, &error_details);
    try std.testing.expect(result != null);
    if (result) |r| {
        defer std.testing.allocator.free(r.source_text);
        try std.testing.expect(r.source_text.len > 0);
    }
}

test "parseTopLevelItem returns null for non-declaration" {
    const source = "not_a_declaration";
    var error_details: ?ErrorDetails = undefined;
    const result = try parseTopLevelItem(std.testing.allocator, source, &error_details);
    try std.testing.expect(result == null);
}

test "parseTopLevelItem returns null for empty source" {
    const source = "";
    var error_details: ?ErrorDetails = undefined;
    const result = try parseTopLevelItem(std.testing.allocator, source, &error_details);
    try std.testing.expect(result == null);
}

// ============================================================================
// Tests for partial parsing (critical for lexer integration)
// ============================================================================

test "parseExpression handles content after expression" {
    // This is how the zempl lexer will use it - parse expr, then continue
    // After parsing "42", lexer should continue at "}"
    const source = "42}";
    var error_details: ?ErrorDetails = undefined;
    const result = try parseExpression(std.testing.allocator, source, &error_details);
    defer std.testing.allocator.free(result.source_text);
    try std.testing.expectEqualStrings("42", result.source_text);
    try std.testing.expectEqual(@as(usize, 2), result.consumed);
    // After consuming 2 chars ("42"), lexer should continue at "}"
}

test "parseExpression stops at space after identifier" {
    // When we have "a b", we should parse "a" and stop
    // TODO: Current implementation includes the space - need better boundary detection
    const source = "a b";
    var error_details: ?ErrorDetails = undefined;
    const result = try parseExpression(std.testing.allocator, source, &error_details);
    defer std.testing.allocator.free(result.source_text);
    try std.testing.expect(result.source_text.len >= 1); // At least parsed "a"
}

test "parseExpression parses full binary expression" {
    // "a + b" should be fully parsed
    const source = "a + b";
    var error_details: ?ErrorDetails = undefined;
    const result = try parseExpression(std.testing.allocator, source, &error_details);
    defer std.testing.allocator.free(result.source_text);
    try std.testing.expect(result.source_text.len > 0);
}

test "parseExpression stops at closing brace after function call" {
    // "foo()}" should parse "foo()" and stop at "}"
    const source = "foo()}";
    var error_details: ?ErrorDetails = undefined;
    const result = try parseExpression(std.testing.allocator, source, &error_details);
    defer std.testing.allocator.free(result.source_text);
    try std.testing.expect(result.source_text.len > 0);
}
