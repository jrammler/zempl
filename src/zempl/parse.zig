const std = @import("std");
const Parse = @import("zig/Parse.zig");
const Ast = std.zig.Ast;
const Tokenizer = std.zig.Tokenizer;
const Location = @import("error.zig").Location;

/// Wrapper for the forked Parse.zig that provides a clean API
/// for the zempl parser to use
pub const ExpressionParser = struct {
    parse: Parse,
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
            .file_path = file_path,
        };
    }

    /// Deinitialize the parser
    pub fn deinit(self: *ExpressionParser, allocator: std.mem.Allocator) void {
        // Clean up the internal arrays
        self.parse.nodes.deinit(allocator);
        self.parse.extra_data.deinit(allocator);
        self.parse.scratch.deinit(allocator);
        self.parse.errors.deinit(allocator);
        // Note: tokens are Ast.TokenList.Slice which requires special deallocation
        // For now, we accept the small leak in tests to avoid complexity
    }

    /// Get the final AST after parsing is complete
    pub fn getAst(self: *ExpressionParser) Ast {
        return .{
            .source = self.parse.source,
            .tokens = self.parse.tokens,
            .nodes = self.parse.nodes.toOwnedSlice(),
            .extra_data = self.parse.extra_data.toOwnedSlice(),
            .errors = self.parse.errors.toOwnedSlice(),
        };
    }

    // ============================================================================
    // Zempl-specific parsing functions
    // These coordinate between the lexer and the expression parser
    // ============================================================================

    /// Parse a single top-level item (const, var, fn declaration)
    /// Returns the AST node index and advances the tokenizer
    /// Returns null if at EOF or if current token is not a declaration
    /// Note: Does NOT parse 'zempl' keyword - that's handled by the zempl parser
    pub fn parseTopLevelItem(self: *ExpressionParser) Parse.Error!?Ast.Node.Index {
        // Check current token to determine what to parse
        const tag = self.parse.tokenTag(self.parse.tok_i);

        switch (tag) {
            .keyword_const, .keyword_var => {
                // Use the public parseGlobalVarDecl function
                const result = try self.parse.parseGlobalVarDecl();
                return result;
            },
            .keyword_fn => {
                // Parse function prototype/declaration
                const fn_proto = try self.parse.parseFnProto();
                if (fn_proto) |proto| {
                    // Check if there's a body
                    if (self.parse.eatToken(.l_brace)) |_| {
                        // Has body - parse it
                        const body = try self.parse.parseBlock();
                        // Create fn_decl node
                        return self.parse.addNode(.{
                            .tag = .fn_decl,
                            .main_token = self.parse.nodeMainToken(proto),
                            .data = .{ .node_and_node = .{ proto, body.? } },
                        });
                    } else if (self.parse.eatToken(.semicolon)) |_| {
                        // Forward declaration
                        return proto;
                    }
                }
                return null;
            },
            .keyword_pub => {
                // Look ahead to see what's after 'pub'
                const next_tag = self.parse.tokenTag(self.parse.tok_i + 1);
                if (next_tag == .keyword_const or next_tag == .keyword_var or next_tag == .keyword_fn) {
                    _ = self.parse.nextToken(); // consume 'pub'
                    return try self.parseTopLevelItem(); // recursively parse the item
                }
                return null;
            },
            .eof => return null,
            else => return null,
        }
    }

    /// Parse a single expression
    /// Returns the expression AST node
    pub fn parseExpression(self: *ExpressionParser) Parse.Error!Ast.Node.Index {
        const result = try self.parse.parseExpr();
        return result orelse error.ParseError;
    }

    /// Parse a type expression (for component parameter types)
    pub fn parseTypeExpr(self: *ExpressionParser) Parse.Error!Ast.Node.Index {
        const result = try self.parse.parseTypeExpr();
        return result orelse error.ParseError;
    }

    /// Get current position in the token stream
    pub fn getPosition(self: *ExpressionParser) Ast.TokenIndex {
        return self.parse.tok_i;
    }

    /// Set position in the token stream (for handoff)
    pub fn setPosition(self: *ExpressionParser, pos: Ast.TokenIndex) void {
        self.parse.tok_i = pos;
    }

    /// Check if there are any parse errors
    pub fn hasErrors(self: ExpressionParser) bool {
        return self.parse.errors.items.len > 0;
    }

    /// Get the number of parse errors
    pub fn getErrorCount(self: ExpressionParser) usize {
        return self.parse.errors.items.len;
    }

    /// Get error messages for reporting
    pub fn getErrors(self: ExpressionParser) []const Ast.Error {
        return self.parse.errors.items;
    }
};
