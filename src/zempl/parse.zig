const std = @import("std");
const Parse = @import("zig/Parse.zig");
const Ast = std.zig.Ast;
const Tokenizer = std.zig.Tokenizer;
const Location = @import("error.zig").Location;

/// Wrapper for the forked Parse.zig that provides a clean API
/// for the zempl parser to use
pub const ExpressionParser = struct {
    parse: Parse,
    ast: Ast,
    tokenizer: Tokenizer,
    file_path: []const u8,

    /// Initialize the expression parser with source code
    pub fn init(allocator: std.mem.Allocator, source: [:0]const u8, file_path: []const u8) !ExpressionParser {
        // Tokenize the source first
        var tokenizer = Tokenizer.init(source);

        // Collect tokens into a list (Parse expects a TokenList)
        var tokens = Ast.TokenList{};
        defer tokens.deinit(allocator);

        while (true) {
            const token = tokenizer.next();
            try tokens.append(allocator, .{
                .tag = token.tag,
                .start = @intCast(token.loc.start),
            });
            if (token.tag == .eof) break;
        }

        // Create the Parse instance
        const parse = Parse{
            .gpa = allocator,
            .source = source,
            .tokens = tokens.toOwnedSlice(),
            .tok_i = 0,
            .errors = .{},
            .nodes = .{},
            .extra_data = .{},
            .scratch = .{},
        };

        return .{
            .parse = parse,
            .ast = undefined, // Will be populated after parsing
            .tokenizer = tokenizer,
            .file_path = file_path,
        };
    }

    /// Deinitialize the parser
    pub fn deinit(self: *ExpressionParser) void {
        // Parse.deinit() doesn't exist, but we need to clean up
        // The Ast owns the memory, so we clean up the Ast
        self.ast.deinit(self.parse.gpa);
    }

    /// Parse a single expression and return the AST node
    pub fn parseExpression(self: *ExpressionParser) !Ast.Node.Index {
        return self.parse.parseExpression();
    }

    /// Parse a top-level declaration (const, var, fn)
    pub fn parseTopLevelItem(self: *ExpressionParser) !?Ast.Node.Index {
        return self.parse.parseTopLevelItem();
    }

    /// Parse a type expression (for parameter types)
    pub fn parseTypeExpr(self: *ExpressionParser) !Ast.Node.Index {
        // Call the internal parseTypeExpr - it returns ?Node.Index
        const result = try self.parse.parseTypeExpr();
        return result orelse error.ParseError;
    }

    /// Parse a parameter declaration list
    pub fn parseParamDeclList(self: *ExpressionParser) !Ast.Node.Index {
        // The internal parseParamDeclList returns SmallSpan, not Node.Index
        // We need to handle this differently
        _ = self;
        @panic("parseParamDeclList not yet implemented - needs to handle SmallSpan");
    }

    /// Get current position in the token stream
    pub fn getPosition(self: ExpressionParser) Ast.TokenIndex {
        return self.parse.getPosition();
    }

    /// Set position in the token stream (for handoff)
    pub fn setPosition(self: *ExpressionParser, pos: Ast.TokenIndex) void {
        self.parse.setPosition(pos);
    }

    /// Get the final AST after parsing is complete
    pub fn getAst(self: *ExpressionParser) Ast {
        // Convert Parse to Ast
        return .{
            .source = self.parse.source,
            .tokens = self.parse.tokens,
            .nodes = self.parse.nodes.toOwnedSlice(),
            .extra_data = self.parse.extra_data.toOwnedSlice(),
            .errors = self.parse.errors.toOwnedSlice(),
        };
    }

    /// Check if there are any parse errors
    pub fn hasErrors(self: ExpressionParser) bool {
        return self.parse.errors.items.len > 0;
    }

    /// Get the number of parse errors
    pub fn getErrorCount(self: ExpressionParser) usize {
        return self.parse.errors.items.len;
    }
};

// Tests
test "ExpressionParser initialization" {
    const allocator = std.testing.allocator;
    const source = "const x = 5;";

    var parser = try ExpressionParser.init(allocator, source, "test.zig");
    defer parser.deinit();

    try std.testing.expectEqual(@as(Ast.TokenIndex, 0), parser.getPosition());
}

test "parseExpression with integer" {
    const allocator = std.testing.allocator;
    const source = "42";

    var parser = try ExpressionParser.init(allocator, source, "test.zig");
    defer parser.deinit();

    const node = try parser.parseExpression();
    try std.testing.expect(node != .none);
}

test "parseTopLevelItem with const" {
    const allocator = std.testing.allocator;
    const source = "const x = 5;";

    var parser = try ExpressionParser.init(allocator, source, "test.zig");
    defer parser.deinit();

    const node = try parser.parseTopLevelItem();
    try std.testing.expect(node != null);
}
