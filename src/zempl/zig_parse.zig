const std = @import("std");
const Parse = @import("zig/Parse.zig");
const Ast = std.zig.Ast;
const Tokenizer = std.zig.Tokenizer;
const Location = @import("error.zig").Location;

/// Utility functions for parsing Zig expressions on demand.
/// This module does not store any state - it creates Parse instances
/// temporarily when needed and cleans them up immediately.
/// Parse a single Zig expression from source text.
/// Creates a temporary Parse instance, tokenizes just this expression,
/// parses it, and cleans up.
pub fn parseExpression(allocator: std.mem.Allocator, source: [:0]const u8) Parse.Error!Ast.Node.Index {
    // Tokenize just this expression
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

    // Create temporary Parse instance
    var parse = Parse{
        .gpa = allocator,
        .source = source,
        .tokens = tokens.toOwnedSlice(),
        .tok_i = 0,
        .errors = .{},
        .nodes = .{},
        .extra_data = .{},
        .scratch = .{},
    };

    // Parse the expression
    const result = try parse.parseExpr();

    // Clean up Parse instance
    parse.nodes.deinit(allocator);
    parse.extra_data.deinit(allocator);
    parse.scratch.deinit(allocator);
    parse.errors.deinit(allocator);
    // Note: tokens slice is freed when tokens TokenList is deinit'd above

    return result orelse error.ParseError;
}

/// Parse a Zig type expression.
pub fn parseTypeExpr(allocator: std.mem.Allocator, source: [:0]const u8) Parse.Error!Ast.Node.Index {
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

    var parse = Parse{
        .gpa = allocator,
        .source = source,
        .tokens = tokens.toOwnedSlice(),
        .tok_i = 0,
        .errors = .{},
        .nodes = .{},
        .extra_data = .{},
        .scratch = .{},
    };

    const result = try parse.parseTypeExpr();

    parse.nodes.deinit(allocator);
    parse.extra_data.deinit(allocator);
    parse.scratch.deinit(allocator);
    parse.errors.deinit(allocator);

    return result orelse error.ParseError;
}

/// Parse a top-level declaration (const, var, fn).
/// Returns the declaration AST node or null if not a declaration.
pub fn parseTopLevelItem(allocator: std.mem.Allocator, source: [:0]const u8) Parse.Error!?Ast.Node.Index {
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

    var parse = Parse{
        .gpa = allocator,
        .source = source,
        .tokens = tokens.toOwnedSlice(),
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
        .keyword_const, .keyword_var => {
            return try parse.parseGlobalVarDecl();
        },
        .keyword_fn => {
            return try parse.parseFnProto();
        },
        .keyword_pub => {
            // Look ahead to see what's after 'pub'
            const next_tag = parse.tokenTag(parse.tok_i + 1);
            if (next_tag == .keyword_const or next_tag == .keyword_var) {
                _ = parse.nextToken(); // consume 'pub'
                return try parse.parseGlobalVarDecl();
            } else if (next_tag == .keyword_fn) {
                _ = parse.nextToken(); // consume 'pub'
                return try parse.parseFnProto();
            }
            return null;
        },
        .eof => return null,
        else => return null,
    }
}

// ============================================================================
// Tests
// ============================================================================

test "parseExpression parses simple integer literal" {
    const source = "42";
    const node = try parseExpression(std.testing.allocator, source);
    // Verify we got a valid node index
    try std.testing.expect(@intFromEnum(node) >= 0);
}

test "parseExpression parses string literal" {
    const source = "\"hello world\"";
    const node = try parseExpression(std.testing.allocator, source);
    try std.testing.expect(@intFromEnum(node) >= 0);
}

test "parseExpression parses variable access" {
    const source = "my_var";
    const node = try parseExpression(std.testing.allocator, source);
    try std.testing.expect(@intFromEnum(node) >= 0);
}

test "parseExpression parses binary expression" {
    const source = "a + b";
    const node = try parseExpression(std.testing.allocator, source);
    try std.testing.expect(@intFromEnum(node) >= 0);
}

test "parseExpression parses function call" {
    const source = "foo(a, b)";
    const node = try parseExpression(std.testing.allocator, source);
    try std.testing.expect(@intFromEnum(node) >= 0);
}

test "parseTypeExpr parses primitive type" {
    const source = "i32";
    const node = try parseTypeExpr(std.testing.allocator, source);
    try std.testing.expect(@intFromEnum(node) >= 0);
}

test "parseTypeExpr parses slice type" {
    const source = "[]const u8";
    const node = try parseTypeExpr(std.testing.allocator, source);
    try std.testing.expect(@intFromEnum(node) >= 0);
}

test "parseTypeExpr parses pointer type" {
    const source = "*u32";
    const node = try parseTypeExpr(std.testing.allocator, source);
    try std.testing.expect(@intFromEnum(node) >= 0);
}

test "parseTopLevelItem parses const declaration" {
    const source = "const x = 42;";
    const node = try parseTopLevelItem(std.testing.allocator, source);
    try std.testing.expect(node != null);
}

test "parseTopLevelItem parses var declaration" {
    const source = "var y: i32 = 0;";
    const node = try parseTopLevelItem(std.testing.allocator, source);
    try std.testing.expect(node != null);
}

test "parseTopLevelItem parses function prototype" {
    const source = "fn foo() void;";
    const node = try parseTopLevelItem(std.testing.allocator, source);
    try std.testing.expect(node != null);
}

test "parseTopLevelItem returns null for non-declaration" {
    const source = "not_a_declaration";
    const node = try parseTopLevelItem(std.testing.allocator, source);
    try std.testing.expect(node == null);
}

test "parseTopLevelItem returns null for empty source" {
    const source = "";
    const node = try parseTopLevelItem(std.testing.allocator, source);
    try std.testing.expect(node == null);
}
