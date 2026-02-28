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
            const token = self.lexer.peek();

            if (token.token_type == .eof) break;

            // Try to parse as Zig top-level item first
            const source_slice: [:0]const u8 = self.lexer.source[start_pos.. :0];

            if (try zig_parse.parseTopLevelItem(self.allocator, source_slice)) |result| {
                // Found a valid Zig declaration
                try items.append(self.allocator, .{ .declaration = result.source_text });

                // Advance lexer by consumed bytes
                self.lexer.advanceBy(result.consumed);
            } else {
                // Not a Zig declaration, try parsing as zempl component
                if (token.token_type == .zempl_keyword) {
                    // Consume the zempl keyword
                    _ = self.lexer.next();
                    const component = try self.parseZemplComponent();
                    try items.append(self.allocator, .{ .component = component });
                } else {
                    return error.UnexpectedToken;
                }
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
    /// Parse a zempl component definition
    fn parseZemplComponent(self: *Parser) !ZemplComponent {
        // Expect component name (identifier)
        const name_token = self.lexer.next();
        if (name_token.token_type != .identifier) {
            return error.ExpectedComponentName;
        }
        const name = try self.allocator.dupe(u8, name_token.text);
        errdefer self.allocator.free(name);

        // Parse parameter list using zig_parse
        const start_pos = self.lexer.getPosition();
        const source_slice: [:0]const u8 = self.lexer.source[start_pos.. :0];

        const params_result = zig_parse.parseParamDeclList(self.allocator, source_slice) catch |err| switch (err) {
            error.ParseError => return error.ExpectedParamList,
            else => |e| return e,
        };
        // Note: params_result.source_text ownership is transferred to the component
        // and will be freed in deinitComponent

        // Advance lexer by consumed bytes
        self.lexer.advanceBy(params_result.consumed);

        // Expect opening brace
        const lbrace_token = self.lexer.next();
        if (lbrace_token.token_type != .lbrace) {
            return error.ExpectedLBrace;
        }

        // Parse body (HTML content)
        const body = try self.parseHtmlBody();

        return ZemplComponent{
            .name = name,
            .is_public = false, // TODO: handle pub zempl
            .params = params_result.source_text,
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

test "parser handles simple zempl component" {
    const source = "zempl Hello() { <div>Hello</div> }";
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
    try std.testing.expect(file.items[0] == .component);
    try std.testing.expectEqualStrings("Hello", file.items[0].component.name);
    try std.testing.expectEqualStrings("()", file.items[0].component.params);
}

test "parser handles zempl component with params" {
    const source = "zempl Greeting(name: []const u8) { <div>Hello</div> }";
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
    try std.testing.expect(file.items[0] == .component);
    try std.testing.expectEqualStrings("Greeting", file.items[0].component.name);
    try std.testing.expectEqualStrings("(name: []const u8)", file.items[0].component.params);
}

test "parser handles multiple declarations" {
    const source = "const x = 1;\nconst y = 2;";
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

    try std.testing.expectEqual(@as(usize, 2), file.items.len);
    try std.testing.expect(file.items[0] == .declaration);
    try std.testing.expect(file.items[1] == .declaration);
}

test "parser handles declaration and component" {
    const source = "const x = 1;\nzempl Hello() { <div>Hello</div> }";
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

    try std.testing.expectEqual(@as(usize, 2), file.items.len);
    try std.testing.expect(file.items[0] == .declaration);
    try std.testing.expect(file.items[1] == .component);
    try std.testing.expectEqualStrings("Hello", file.items[1].component.name);
}
