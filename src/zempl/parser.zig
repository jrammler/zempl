const std = @import("std");
const ZemplFile = @import("ast.zig").ZemplFile;
const ZemplItem = @import("ast.zig").ZemplItem;
const ZemplComponent = @import("ast.zig").ZemplComponent;
const HtmlNode = @import("ast.zig").HtmlNode;
const HtmlElement = @import("ast.zig").HtmlElement;
const HtmlAttribute = @import("ast.zig").HtmlAttribute;
const Lexer = @import("lexer.zig").Lexer;
const ExpressionParser = @import("parse.zig").ExpressionParser;
const Location = @import("error.zig").Location;

/// Parser for zempl files - coordinates lexer, HTML parsing, and expression parsing
pub const Parser = struct {
    lexer: *Lexer,
    expression_parser: *ExpressionParser,
    allocator: std.mem.Allocator,
    file_path: []const u8,

    /// HTML void elements (self-closing, no content allowed)
    const void_elements = [_][]const u8{
        "area",  "base", "br",   "col",   "embed",  "hr",    "img",
        "input", "link", "meta", "param", "source", "track", "wbr",
    };

    /// Initialize the parser
    pub fn init(lexer: *Lexer, expression_parser: *ExpressionParser, allocator: std.mem.Allocator, file_path: []const u8) Parser {
        return .{
            .lexer = lexer,
            .expression_parser = expression_parser,
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

        // TODO: Implement top-level parsing
        // For now, return empty file

        return ZemplFile{
            .items = try items.toOwnedSlice(self.allocator),
            .location = .{
                .file_path = self.file_path,
                .line = 1,
                .column = 1,
            },
        };
    }

    /// Helper to deinit a ZemplItem
    fn deinitZemplItem(self: *Parser, item: *ZemplItem) void {
        switch (item.*) {
            .declaration => |decl| {
                // Declarations are owned by expression parser
                _ = decl;
            },
            .component => |*comp| {
                self.deinitComponent(comp);
            },
        }
    }

    /// Helper to deinit a component
    fn deinitComponent(self: *Parser, comp: *ZemplComponent) void {
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
            .expression => {},
            .code_block => {},
            .control_flow => {},
            .component_call => {},
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "parser initialization" {
    const source = "<div></div>";
    var lexer = Lexer.init(source, "test.zempl");
    var expr_parser = try ExpressionParser.init(std.testing.allocator, source, "test.zempl");
    defer expr_parser.deinit(std.testing.allocator);

    const parser = Parser.init(&lexer, &expr_parser, std.testing.allocator, "test.zempl");

    try std.testing.expectEqual(&lexer, parser.lexer);
    try std.testing.expectEqual(&expr_parser, parser.expression_parser);
    try std.testing.expectEqualStrings("test.zempl", parser.file_path);
}

test "parser returns empty file for empty input" {
    const source = "";
    var lexer = Lexer.init(source, "test.zempl");
    var expr_parser = try ExpressionParser.init(std.testing.allocator, source, "test.zempl");
    defer expr_parser.deinit(std.testing.allocator);

    const parser = Parser.init(&lexer, &expr_parser, std.testing.allocator, "test.zempl");
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
