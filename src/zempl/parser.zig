const std = @import("std");
const ZemplFile = @import("ast.zig").ZemplFile;
const ZemplItem = @import("ast.zig").ZemplItem;
const ZemplComponent = @import("ast.zig").ZemplComponent;
const HtmlNode = @import("ast.zig").HtmlNode;
const HtmlElement = @import("ast.zig").HtmlElement;
const HtmlAttribute = @import("ast.zig").HtmlAttribute;
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;
const TokenType = @import("lexer.zig").TokenType;
const zig_parse = @import("zig_parse.zig");
const Location = @import("error.zig").Location;

/// Parser for zempl files - coordinates lexer, HTML parsing, and expression parsing
pub const Parser = struct {
    lexer: *Lexer,
    allocator: std.mem.Allocator,
    file_path: []const u8,

    /// HTML void elements (self-closing, no content allowed)
    const void_elements = [_][]const u8{
        "area",  "base", "br",   "col",   "embed",  "hr",    "img",
        "input", "link", "meta", "param", "source", "track", "wbr",
    };

    /// Initialize the parser
    pub fn init(lexer: *Lexer, allocator: std.mem.Allocator, file_path: []const u8) Parser {
        return .{
            .lexer = lexer,
            .allocator = allocator,
            .file_path = file_path,
        };
    }

    /// Parse a complete zempl file
    pub fn parseFile(self: *Parser) !ZemplFile {
        var items = std.ArrayList(ZemplItem).empty;
        errdefer {
            for (items.items) |*item| {
                self.deinitZemplItem(item);
            }
            items.deinit(self.allocator);
        }

        // Parse top-level items until EOF
        while (true) {
            const start_pos = self.lexer.getPosition();
            const token = self.lexer.next();

            switch (token.token_type) {
                .eof => break,
                .identifier => {
                    // Check if it's a top-level declaration or zempl component
                    if (std.mem.eql(u8, token.text, "const") or
                        std.mem.eql(u8, token.text, "var") or
                        std.mem.eql(u8, token.text, "fn") or
                        std.mem.eql(u8, token.text, "pub"))
                    {
                        // Parse Zig declaration
                        const decl_source = try self.parseDeclaration(start_pos);
                        defer self.allocator.free(decl_source);

                        // Validate with zig_parse
                        const sentinel_source = try self.allocator.dupeZ(u8, decl_source);
                        defer self.allocator.free(sentinel_source);

                        if (try zig_parse.parseTopLevelItem(self.allocator, sentinel_source)) |result| {
                            // Note: result.source_text is allocated by zig_parse and ownership is transferred to items
                            try items.append(self.allocator, .{ .declaration = result.source_text });
                        } else {
                            return error.InvalidDeclaration;
                        }
                    } else if (std.mem.eql(u8, token.text, "zempl")) {
                        // Parse zempl component
                        const component = try self.parseZemplComponent();
                        try items.append(self.allocator, .{ .component = component });
                    } else {
                        return error.UnexpectedToken;
                    }
                },
                else => {
                    return error.UnexpectedToken;
                },
            }
        }

        return ZemplFile{
            .items = try items.toOwnedSlice(self.allocator),
            .location = .{
                .file_path = self.file_path,
                .line = 1,
                .column = 1,
            },
        };
    }

    /// Parse a Zig declaration from current position
    /// start_pos is the position in the source where the declaration begins
    fn parseDeclaration(self: *Parser, start_pos: usize) ![]const u8 {
        // We need to find the end of the declaration
        // A declaration ends with ';' or with a block '{ ... }'

        var paren_depth: i32 = 0;
        var brace_depth: i32 = 0;
        var found_semicolon = false;

        // Continue parsing tokens until we reach the end of the declaration
        while (true) {
            const token = self.lexer.next();

            switch (token.token_type) {
                .eof => break,
                .text => {
                    // Check for semicolon, braces, parens
                    for (token.text) |c| {
                        switch (c) {
                            '(' => paren_depth += 1,
                            ')' => paren_depth -= 1,
                            '{' => brace_depth += 1,
                            '}' => brace_depth -= 1,
                            ';' => if (paren_depth == 0 and brace_depth == 0) {
                                found_semicolon = true;
                            },
                            else => {},
                        }
                    }
                },
                else => {},
            }

            // End conditions:
            // 1. Found semicolon at top level (paren_depth == 0, brace_depth == 0)
            // 2. Found closing brace at brace_depth == -1 (end of function body)
            if (found_semicolon) break;
            if (brace_depth < 0) break; // End of function with body
        }

        // Extract the declaration text from source
        const end_pos = self.lexer.getPosition();
        const decl_text = self.lexer.source[start_pos..end_pos];

        return try self.allocator.dupe(u8, decl_text);
    }

    /// Parse a zempl component definition
    fn parseZemplComponent(self: *Parser) !ZemplComponent {
        // Expect component name (identifier)
        const name_token = self.lexer.next();
        if (name_token.token_type != .identifier) {
            return error.ExpectedComponentName;
        }
        const name = try self.allocator.dupe(u8, name_token.text);
        errdefer self.allocator.free(name);

        // Expect parameter list (parentheses with content)
        // For now, just skip to the opening brace
        var paren_depth: i32 = 0;
        var found_paren = false;

        while (true) {
            const token = self.lexer.next();
            switch (token.token_type) {
                .lbrace => {
                    if (paren_depth == 0 and found_paren) {
                        // We've reached the body opening brace
                        break;
                    }
                },
                else => {
                    if (!found_paren and token.token_type == .text and token.text[0] == '(') {
                        found_paren = true;
                        paren_depth = 1;
                    }
                },
            }
        }

        // Parse body (HTML content)
        const body = try self.parseHtmlBody();

        return ZemplComponent{
            .name = name,
            .is_public = false, // TODO: handle pub zempl
            .params = "", // TODO: parse params properly
            .body = body,
            .location = name_token.location,
        };
    }

    /// Parse HTML body content
    fn parseHtmlBody(self: *Parser) ![]HtmlNode {
        var nodes = std.ArrayList(HtmlNode).empty;
        errdefer {
            for (nodes.items) |*node| {
                self.deinitHtmlNode(node);
            }
            nodes.deinit(self.allocator);
        }

        // TODO: Implement actual HTML parsing
        // For now, just consume until closing brace
        while (true) {
            const token = self.lexer.next();
            switch (token.token_type) {
                .rbrace => break,
                .eof => return error.UnexpectedEof,
                else => {
                    // Skip for now
                },
            }
        }

        return nodes.toOwnedSlice(self.allocator);
    }

    /// Helper to deinit a ZemplItem
    fn deinitZemplItem(self: *Parser, item: *ZemplItem) void {
        switch (item.*) {
            .declaration => |decl| {
                self.allocator.free(decl);
            },
            .component => |*comp| {
                self.deinitComponent(comp);
            },
        }
    }

    /// Helper to deinit a component
    fn deinitComponent(self: *Parser, comp: *ZemplComponent) void {
        self.allocator.free(comp.name);
        self.allocator.free(comp.params);
        for (comp.body) |*node| {
            self.deinitHtmlNode(node);
        }
        self.allocator.free(comp.body);
    }

    /// Helper to deinit an HTML node
    fn deinitHtmlNode(self: *Parser, node: *HtmlNode) void {
        switch (node.*) {
            .element => |*elem| {
                for (elem.attributes) |*attr| {
                    self.allocator.free(attr.name);
                    self.allocator.free(attr.value);
                }
                self.allocator.free(elem.attributes);
                for (elem.children) |*child| {
                    self.deinitHtmlNode(child);
                }
                self.allocator.free(elem.children);
                self.allocator.free(elem.tag_name);
            },
            .text => |*text| {
                self.allocator.free(text.content);
            },
            .comment => |*comment| {
                self.allocator.free(comment.content);
            },
            .doctype => |*doctype| {
                self.allocator.free(doctype.content);
            },
            .expression => |*expr| {
                self.allocator.free(expr.expr);
            },
            .code_block => |*block| {
                self.allocator.free(block.statements);
            },
            .control_flow => |*ctrl| {
                self.deinitControlFlow(ctrl);
            },
            .component_call => |*call| {
                self.allocator.free(call.component_name);
                for (call.args) |*arg| {
                    self.allocator.free(arg.expr);
                }
                self.allocator.free(call.args);
            },
        }
    }

    fn deinitControlFlow(self: *Parser, ctrl: anytype) void {
        _ = self;
        _ = ctrl;
        // TODO: Implement control flow cleanup
    }
};

// ============================================================================
// Tests
// ============================================================================

test "parser initialization" {
    const source = "<div></div>";
    var lexer = Lexer.init(source, "test.zempl");

    const parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");

    try std.testing.expectEqual(&lexer, parser.lexer);
    try std.testing.expectEqualStrings("test.zempl", parser.file_path);
}

test "parser returns empty file for empty input" {
    const source = "";
    var lexer = Lexer.init(source, "test.zempl");

    const parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    var mutable_parser = parser;
    const file = try mutable_parser.parseFile();
    defer {
        for (file.items) |*item| {
            mutable_parser.deinitZemplItem(item);
        }
        std.testing.allocator.free(file.items);
    }

    try std.testing.expectEqual(@as(usize, 0), file.items.len);
}

test "parser handles simple const declaration" {
    const source = "const x = 42;";
    var lexer = Lexer.init(source, "test.zempl");

    const parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    var mutable_parser = parser;
    const file = try mutable_parser.parseFile();
    defer {
        for (file.items) |*item| {
            mutable_parser.deinitZemplItem(item);
        }
        std.testing.allocator.free(file.items);
    }

    try std.testing.expectEqual(@as(usize, 1), file.items.len);
    try std.testing.expect(file.items[0] == .declaration);
}
