const std = @import("std");
const ZemplFile = @import("ast.zig").ZemplFile;
const ZemplItem = @import("ast.zig").ZemplItem;
const ZemplComponent = @import("ast.zig").ZemplComponent;
const ZemplImport = @import("ast.zig").ZemplImport;
const HtmlNode = @import("ast.zig").HtmlNode;
const HtmlElement = @import("ast.zig").HtmlElement;
const HtmlAttribute = @import("ast.zig").HtmlAttribute;
const ZemplArg = @import("ast.zig").ZemplArg;
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;
const TokenType = @import("lexer.zig").TokenType;
const Location = @import("lexer.zig").Location;
const ErrorDetails = @import("error.zig").ErrorDetails;
const zig_parse = @import("zig_parse.zig");

/// Parser for zempl files - coordinates lexer, HTML parsing, and expression parsing
pub const Parser = struct {
    lexer: *Lexer,
    allocator: std.mem.Allocator,
    file_path: []const u8,
    error_details: ?ErrorDetails,

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
            .error_details = null,
        };
    }

    fn setError(self: *Parser, location: Location, message: []const u8) void {
        const line_end = if (std.mem.indexOfScalar(u8, self.lexer.source[location.row_start..], '\n')) |line_len| location.row_start + line_len else self.lexer.source.len;
        self.error_details = .{
            .location = location,
            .message = message,
            .line = self.lexer.source[location.row_start..line_end],
        };
    }

    /// Parse a complete zempl file
    pub fn parseFile(self: *Parser) error{ ParseError, OutOfMemory }!ZemplFile {
        var items = std.ArrayList(ZemplItem).empty;
        errdefer {
            for (items.items) |item| {
                item.deinit(self.allocator);
            }
            items.deinit(self.allocator);
        }

        while (self.lexer.peek().token_type != .eof) {
            if (try self.tryParseZimport()) |import_item| {
                try items.append(self.allocator, .{ .import = import_item });
                continue;
            }

            if (try self.parseTopLevelItem()) |item| {
                try items.append(self.allocator, .{ .declaration = item });
                continue;
            }

            const component = try self.parseZemplComponent();
            try items.append(self.allocator, .{ .component = component });
        }

        return ZemplFile{
            .items = try items.toOwnedSlice(self.allocator),
        };
    }

    fn tryParseZimport(self: *Parser) error{ ParseError, OutOfMemory }!?ZemplImport {
        var lexer = self.lexer.*;

        var is_public = false;
        var first_token = lexer.next();
        if (first_token.token_type == .identifier and std.mem.eql(u8, first_token.text, "pub")) {
            is_public = true;
            first_token = lexer.next();
        }

        if (first_token.token_type != .identifier or !std.mem.eql(u8, first_token.text, "const")) {
            return null;
        }

        const name_token = lexer.next();
        if (name_token.token_type != .identifier) {
            return null;
        }

        const eq_token = lexer.next();
        if (eq_token.token_type != .equal) {
            return null;
        }

        const zimport_token = lexer.next();
        if (zimport_token.token_type != .identifier or !std.mem.eql(u8, zimport_token.text, "zimport")) {
            return null;
        }

        const lparen_token = lexer.next();
        if (lparen_token.token_type != .lparen) {
            return null;
        }

        const path_token = lexer.next();
        if (path_token.token_type != .string) {
            return null;
        }

        const rparen_token = lexer.next();
        if (rparen_token.token_type != .rparen) {
            return null;
        }

        const semi_token = lexer.next();
        if (semi_token.token_type != .semicolon) {
            return null;
        }

        const const_name = try self.allocator.dupe(u8, name_token.text);
        errdefer self.allocator.free(const_name);

        const path_text = path_token.text;
        const path = if (path_text.len >= 2 and path_text[0] == '"' and path_text[path_text.len - 1] == '"')
            try self.allocator.dupe(u8, path_text[1 .. path_text.len - 1])
        else
            try self.allocator.dupe(u8, path_text);

        self.lexer.* = lexer;
        return ZemplImport{
            .const_name = const_name,
            .path = path,
            .is_public = is_public,
        };
    }

    fn parseTopLevelItem(self: *Parser) error{ ParseError, OutOfMemory }!?[]const u8 {
        const start_pos = self.lexer.getPosition();
        const source_slice = self.lexer.source[start_pos..];

        const parse_result = try zig_parse.parseTopLevelItem(self.allocator, source_slice, &self.error_details);

        if (parse_result) |result| {
            self.lexer.advanceBy(result.consumed);
            return result.source_text;
        }
        return null;
    }

    fn parseExpression(self: *Parser) error{ ParseError, OutOfMemory }![]const u8 {
        const start_pos = self.lexer.getPosition();
        const source_slice = self.lexer.source[start_pos..];

        const parse_result = try zig_parse.parseExpression(self.allocator, source_slice, &self.error_details);

        self.lexer.advanceBy(parse_result.consumed);
        return parse_result.source_text;
    }

    fn parseParamDeclList(self: *Parser) error{ ParseError, OutOfMemory }![]const u8 {
        const start_pos = self.lexer.getPosition();
        const source_slice = self.lexer.source[start_pos..];

        const parse_result = try zig_parse.parseParamDeclList(self.allocator, source_slice, &self.error_details);

        self.lexer.advanceBy(parse_result.consumed);
        return parse_result.source_text;
    }

    /// Parse a zempl component definition
    /// Handles both "zempl Name() {}" and "pub zempl Name() {}"
    fn parseZemplComponent(self: *Parser) error{ ParseError, OutOfMemory }!ZemplComponent {
        var is_public = false;
        const first_token = self.lexer.peek();
        if (first_token.token_type == .identifier and std.mem.eql(u8, first_token.text, "pub")) {
            _ = self.lexer.next();
            is_public = true;
        }

        const zempl_token = self.lexer.next();
        if (zempl_token.token_type != .identifier) {
            self.setError(zempl_token.location, "expected 'zempl' keyword");
            return error.ParseError;
        }
        if (!std.mem.eql(u8, zempl_token.text, "zempl")) {
            self.setError(zempl_token.location, "expected 'zempl' keyword");
            return error.ParseError;
        }

        const name_token = self.lexer.next();
        if (name_token.token_type != .identifier) {
            self.setError(name_token.location, "expected component name");
            return error.ParseError;
        }
        const name = try self.allocator.dupe(u8, name_token.text);
        errdefer self.allocator.free(name);

        const params = try self.parseParamDeclList();
        errdefer self.allocator.free(params);

        const lbrace_token = self.lexer.next();
        if (lbrace_token.token_type != .lbrace) {
            self.setError(lbrace_token.location, "expected '{'");
            return error.ParseError;
        }

        const body = try self.parseHtmlBody("");

        return ZemplComponent{
            .name = name,
            .is_public = is_public,
            .params = params,
            .body = body,
        };
    }

    /// Parse HTML body content
    /// current_tag_name is an empty string if we are not inside a tag but a block enclosed by braces
    fn parseHtmlBody(self: *Parser, current_tag_name: []const u8) error{ ParseError, OutOfMemory }![]HtmlNode {
        var nodes = std.ArrayList(HtmlNode).empty;
        errdefer {
            for (nodes.items) |*node| {
                node.deinit(self.allocator);
            }
            nodes.deinit(self.allocator);
        }

        while (true) {
            const token = self.lexer.peek();
            token: switch (token.token_type) {
                .rbrace => {
                    _ = self.lexer.next();
                    if (current_tag_name.len > 0) {
                        self.setError(token.location, "unexpected '}'");
                        return error.ParseError;
                    }
                    break;
                },
                .langle => {
                    const node_opt = try self.parseHtmlElementOrComment(current_tag_name);
                    if (node_opt) |node| {
                        try nodes.append(self.allocator, node);
                    } else break;
                },
                .lbrace => {
                    const node = try self.parseExpressionInterpolation();
                    try nodes.append(self.allocator, node);
                },
                .at_lbrace => {
                    const node = try self.parseCodeBlock();
                    try nodes.append(self.allocator, node);
                },
                .identifier => {
                    if (std.mem.startsWith(u8, token.text, "@")) {
                        const node = try self.parseZemplConstruct();
                        try nodes.append(self.allocator, node);
                    } else {
                        continue :token .text;
                    }
                },
                else => {
                    const node = try self.parseTextContent();
                    try nodes.append(self.allocator, node);
                },
            }
        }

        return nodes.toOwnedSlice(self.allocator);
    }

    /// Parse an HTML element, comment, or DOCTYPE
    /// Returns null if this closes the current element
    fn parseHtmlElementOrComment(self: *Parser, current_tag_name: []const u8) error{ ParseError, OutOfMemory }!?HtmlNode {
        _ = self.lexer.next().location; // consume '<'

        const next_token = self.lexer.peek();
        if (next_token.token_type == .bang) {
            _ = self.lexer.next();
            return try self.parseDeclaration();
        }

        if (next_token.token_type == .slash) {
            _ = self.lexer.next();
            const name = self.lexer.next();
            if (name.token_type != .identifier) {
                self.setError(name.location, "expected identifier");
                return error.ParseError;
            }
            if (!std.mem.eql(u8, name.text, current_tag_name)) {
                self.setError(name.location, "unexpected closing tag");
                return error.ParseError;
            }
            if (self.lexer.next().token_type != .rangle) {
                self.setError(self.lexer.peek().location, "expected '>'");
                return error.ParseError;
            }
            return null;
        }

        return try self.parseElement();
    }

    /// Parse HTML declaration (comment or doctype declaration)
    fn parseDeclaration(self: *Parser) error{ ParseError, OutOfMemory }!HtmlNode {
        const text_token = self.lexer.nextContent();

        const rangle = self.lexer.next();
        if (rangle.token_type != .rangle) {
            self.setError(rangle.location, "unclosed comment");
            return error.ParseError;
        }

        return HtmlNode{
            .declaration = .{
                .content = try self.allocator.dupe(u8, text_token.text),
            },
        };
    }

    /// Parse element start tag and its content
    fn parseElement(self: *Parser) error{ ParseError, OutOfMemory }!HtmlNode {
        const tag_token = self.lexer.next();
        if (tag_token.token_type != .identifier) {
            self.setError(tag_token.location, "expected tag name");
            return error.ParseError;
        }
        const tag_name = try self.allocator.dupe(u8, tag_token.text);
        errdefer self.allocator.free(tag_name);

        var attributes = std.ArrayList(HtmlAttribute).empty;
        errdefer {
            for (attributes.items) |attr| {
                attr.deinit(self.allocator);
            }
            attributes.deinit(self.allocator);
        }

        while (true) {
            const token = self.lexer.peek();
            switch (token.token_type) {
                .rangle, .slash, .eof => break,
                .identifier => {
                    const attr = try self.parseAttribute();
                    try attributes.append(self.allocator, attr);
                },
                else => {
                    _ = self.lexer.next();
                },
            }
        }

        const is_void = isVoidElement(tag_name);
        var is_self_closing = false;

        const next_token = self.lexer.peek();
        if (next_token.token_type == .slash) {
            _ = self.lexer.next();
            is_self_closing = true;
        }

        const rangle_token = self.lexer.next();
        if (rangle_token.token_type != .rangle) {
            self.setError(rangle_token.location, "expected '>'");
            return error.ParseError;
        }

        if (is_void or is_self_closing) {
            return HtmlNode{ .element = .{
                .tag_name = tag_name,
                .attributes = try attributes.toOwnedSlice(self.allocator),
                .children = &.{},
                .is_void = true,
            } };
        }

        const children = try self.parseHtmlBody(tag_name);

        return HtmlNode{ .element = .{
            .tag_name = tag_name,
            .attributes = try attributes.toOwnedSlice(self.allocator),
            .children = children,
            .is_void = false,
        } };
    }

    /// Parse an HTML attribute
    fn parseAttribute(self: *Parser) error{ ParseError, OutOfMemory }!HtmlAttribute {
        const name_token = self.lexer.next();
        if (name_token.token_type != .identifier) {
            self.setError(name_token.location, "expected attribute name");
            return error.ParseError;
        }
        const name = try self.allocator.dupe(u8, name_token.text);
        errdefer self.allocator.free(name);

        var value: []const u8 = "";

        if (self.lexer.peek().token_type == .equal) {
            _ = self.lexer.next();

            const next_token = self.lexer.peek();
            if (next_token.token_type == .lbrace) {
                _ = self.lexer.next();
                value = try self.parseExpression();
                if (self.lexer.next().token_type != .rbrace) {
                    self.setError(self.lexer.peek().location, "expected '}'");
                    return error.ParseError;
                }
            } else {
                if (next_token.token_type != .string) {
                    self.setError(next_token.location, "expected string");
                    return error.ParseError;
                }
                value = try self.allocator.dupe(u8, next_token.text);
            }
        } else {
            value = try self.allocator.dupe(u8, "true");
        }

        return HtmlAttribute{
            .name = name,
            .value = value,
        };
    }

    /// Parse text content using nextContent
    fn parseTextContent(self: *Parser) error{ ParseError, OutOfMemory }!HtmlNode {
        const token = self.lexer.nextContent();

        if (token.token_type == .eof) {
            self.setError(token.location, "unexpected end of file");
            return error.ParseError;
        }

        std.debug.assert(token.token_type == .text);

        return HtmlNode{ .text = .{
            .content = try self.allocator.dupe(u8, token.text),
        } };
    }

    /// Parse expression interpolation {expr}
    fn parseExpressionInterpolation(self: *Parser) error{ ParseError, OutOfMemory }!HtmlNode {
        const lbrace_token = self.lexer.next();

        const expr = try self.parseExpression();
        errdefer self.allocator.free(expr);

        if (self.lexer.next().token_type != .rbrace) {
            self.setError(lbrace_token.location, "expected '}'");
            return error.ParseError;
        }

        return HtmlNode{ .expression = .{
            .expr = expr,
        } };
    }

    /// Parse zempl constructs (@if, @for, @while, @Component)
    fn parseZemplConstruct(self: *Parser) error{ ParseError, OutOfMemory }!HtmlNode {
        const at_token = self.lexer.next();
        const construct_name = at_token.text;

        if (std.mem.eql(u8, construct_name, "@if")) {
            return self.parseIfStatement();
        } else if (std.mem.eql(u8, construct_name, "@for")) {
            return self.parseForLoop();
        } else if (std.mem.eql(u8, construct_name, "@while")) {
            return self.parseWhileLoop();
        } else if (construct_name.len > 1 and std.ascii.isUpper(construct_name[1])) {
            return self.parseComponentCall(construct_name);
        } else {
            self.setError(at_token.location, "unknown zempl construct");
            return error.ParseError;
        }
    }

    /// Parse @if statement
    fn parseIfStatement(self: *Parser) error{ ParseError, OutOfMemory }!HtmlNode {
        const lparen_token = self.lexer.next();
        if (lparen_token.token_type != .lparen) {
            self.setError(lparen_token.location, "expected '('");
            return error.ParseError;
        }

        const condition = try self.parseExpression();
        errdefer self.allocator.free(condition);

        const rparen_token = self.lexer.next();
        if (rparen_token.token_type != .rparen) {
            self.setError(rparen_token.location, "expected ')'");
            return error.ParseError;
        }

        const lbrace_token = self.lexer.next();
        if (lbrace_token.token_type != .lbrace) {
            self.setError(lbrace_token.location, "expected '{'");
            return error.ParseError;
        }

        const then_body = try self.parseHtmlBody("");
        errdefer {
            for (then_body) |*node| {
                node.deinit(self.allocator);
            }
            self.allocator.free(then_body);
        }

        var else_body: ?[]HtmlNode = null;
        const next_token = self.lexer.peek();
        if (next_token.token_type == .identifier and std.mem.eql(u8, next_token.text, "@else")) {
            _ = self.lexer.next();

            const else_lbrace = self.lexer.next();
            if (else_lbrace.token_type != .lbrace) {
                self.setError(else_lbrace.location, "expected '{'");
                return error.ParseError;
            }

            else_body = try self.parseHtmlBody("");
        }

        return HtmlNode{ .control_flow = .{ .if_stmt = .{
            .condition = condition,
            .then_body = then_body,
            .else_body = else_body,
        } } };
    }

    /// Parse @for loop
    fn parseForLoop(self: *Parser) error{ ParseError, OutOfMemory }!HtmlNode {
        const lparen_token = self.lexer.next();
        if (lparen_token.token_type != .lparen) {
            self.setError(lparen_token.location, "expected '('");
            return error.ParseError;
        }

        var iterables = std.ArrayList([]const u8).empty;
        errdefer {
            for (iterables.items) |iterable| {
                self.allocator.free(iterable);
            }
            iterables.deinit(self.allocator);
        }

        while (true) {
            const iterable = try self.parseExpression();
            errdefer self.allocator.free(iterable);
            try iterables.append(self.allocator, iterable);
            if (self.lexer.peek().token_type != .comma) break;
        }

        const rparen_token = self.lexer.next();
        if (rparen_token.token_type != .rparen) {
            self.setError(rparen_token.location, "expected ')'");
            return error.ParseError;
        }

        const first_pipe = self.lexer.next();
        if (first_pipe.token_type != .pipe) {
            self.setError(first_pipe.location, "expected '|'");
            return error.ParseError;
        }

        var captures = std.ArrayList([]const u8).empty;
        errdefer {
            for (captures.items) |capture| {
                self.allocator.free(capture);
            }
            captures.deinit(self.allocator);
        }

        while (true) {
            const capture = self.lexer.next();
            if (capture.token_type != .identifier) {
                self.setError(capture.location, "expected identifier");
                return error.ParseError;
            }
            try captures.append(self.allocator, try self.allocator.dupe(u8, capture.text));
            if (self.lexer.peek().token_type != .comma) break;
        }

        const second_pipe = self.lexer.next();
        if (second_pipe.token_type != .pipe) {
            self.setError(second_pipe.location, "expected '|'");
            return error.ParseError;
        }

        const lbrace_token = self.lexer.next();
        if (lbrace_token.token_type != .lbrace) {
            self.setError(lbrace_token.location, "expected '{'");
            return error.ParseError;
        }

        const body = try self.parseHtmlBody("");

        return HtmlNode{ .control_flow = .{ .for_loop = .{
            .captures = try captures.toOwnedSlice(self.allocator),
            .iterables = try iterables.toOwnedSlice(self.allocator),
            .body = body,
        } } };
    }

    /// Parse @while loop
    fn parseWhileLoop(self: *Parser) error{ ParseError, OutOfMemory }!HtmlNode {
        const lparen_token = self.lexer.next();
        if (lparen_token.token_type != .lparen) {
            self.setError(lparen_token.location, "expected '('");
            return error.ParseError;
        }

        const condition = try self.parseExpression();
        errdefer self.allocator.free(condition);

        const rparen_token = self.lexer.next();
        if (rparen_token.token_type != .rparen) {
            self.setError(rparen_token.location, "expected ')'");
            return error.ParseError;
        }

        const lbrace_token = self.lexer.next();
        if (lbrace_token.token_type != .lbrace) {
            self.setError(lbrace_token.location, "expected '{'");
            return error.ParseError;
        }

        const body = try self.parseHtmlBody("");

        return HtmlNode{ .control_flow = .{ .while_loop = .{
            .condition = condition,
            .body = body,
        } } };
    }

    /// Parse @{...} code block
    fn parseCodeBlock(self: *Parser) error{ ParseError, OutOfMemory }!HtmlNode {
        const at_lbrace_token = self.lexer.next();

        const start_pos = self.lexer.getPosition();

        var brace_depth: i32 = 1;
        while (brace_depth > 0) {
            const token = self.lexer.next();
            switch (token.token_type) {
                .lbrace => brace_depth += 1,
                .rbrace => brace_depth -= 1,
                .eof => {
                    self.setError(at_lbrace_token.location, "unclosed code block");
                    return error.ParseError;
                },
                else => {},
            }
        }

        const end_pos = self.lexer.getPosition() - 1;
        const statements = self.lexer.source[start_pos..end_pos];

        return HtmlNode{ .code_block = .{
            .statements = try self.allocator.dupe(u8, statements),
        } };
    }

    /// Parse @Component(...) call
    fn parseComponentCall(self: *Parser, component_name: []const u8) error{ ParseError, OutOfMemory }!HtmlNode {
        const name = try self.allocator.dupe(u8, component_name[1..]);
        errdefer self.allocator.free(name);

        var args = std.ArrayList(ZemplArg).empty;
        errdefer {
            for (args.items) |arg| {
                arg.deinit(self.allocator);
            }
            args.deinit(self.allocator);
        }

        const lparen_token = self.lexer.next();
        if (lparen_token.token_type != .lparen) {
            self.setError(lparen_token.location, "expected '('");
            return error.ParseError;
        }

        while (true) {
            const token = self.lexer.peek();

            if (token.token_type == .eof) {
                self.setError(token.location, "unexpected end of file");
                return error.ParseError;
            }

            if (token.token_type == .rparen) {
                _ = self.lexer.next();
                break;
            }

            const arg = try self.parseExpression();

            try args.append(self.allocator, .{
                .expr = arg,
            });

            const end_token = self.lexer.next();
            if (end_token.token_type == .rparen) {
                break;
            }
            if (end_token.token_type != .comma) {
                self.setError(end_token.location, "expected ',' or ')'");
                return error.ParseError;
            }
        }

        return HtmlNode{ .component_call = .{
            .component_name = name,
            .args = try args.toOwnedSlice(self.allocator),
        } };
    }

    /// Check if tag name is a void element
    fn isVoidElement(tag_name: []const u8) bool {
        const void_tags = .{
            "area",  "base", "br",   "col",   "embed",  "hr",    "img",
            "input", "link", "meta", "param", "source", "track", "wbr",
        };
        inline for (void_tags) |void_tag| {
            if (std.mem.eql(u8, tag_name, void_tag)) return true;
        }
        return false;
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

    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), file.items.len);
}

test "parser handles simple const declaration" {
    const source = "const x = 42;";
    var lexer = Lexer.init(source, "test.zempl");

    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), file.items.len);
    try std.testing.expect(file.items[0] == .declaration);
}

test "parser handles simple zempl component" {
    const source = "zempl Hello() { <div>Hello</div> }";
    var lexer = Lexer.init(source, "test.zempl");

    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), file.items.len);
    try std.testing.expect(file.items[0] == .component);
    try std.testing.expectEqualStrings("Hello", file.items[0].component.name);
    try std.testing.expectEqualStrings("()", file.items[0].component.params);
}

test "parser handles zempl component with params" {
    const source = "zempl Greeting(name: []const u8) { <div>Hello</div> }";
    var lexer = Lexer.init(source, "test.zempl");

    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), file.items.len);
    try std.testing.expect(file.items[0] == .component);
    try std.testing.expectEqualStrings("Greeting", file.items[0].component.name);
    try std.testing.expectEqualStrings("(name: []const u8)", file.items[0].component.params);
}

test "parser handles pub zempl component" {
    const source = "pub zempl PublicComponent() { <div>Public</div> }";
    var lexer = Lexer.init(source, "test.zempl");

    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), file.items.len);
    try std.testing.expect(file.items[0] == .component);
    try std.testing.expectEqualStrings("PublicComponent", file.items[0].component.name);
    try std.testing.expect(file.items[0].component.is_public);
    try std.testing.expectEqualStrings("()", file.items[0].component.params);
}

test "parser handles multiple declarations" {
    const source = "const x = 1;\nconst y = 2;";
    var lexer = Lexer.init(source, "test.zempl");

    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), file.items.len);
    try std.testing.expect(file.items[0] == .declaration);
    try std.testing.expect(file.items[1] == .declaration);
}

test "parser handles declaration and component" {
    const source = "const x = 1;\nzempl Hello() { <div>Hello</div> }";
    var lexer = Lexer.init(source, "test.zempl");

    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), file.items.len);
    try std.testing.expect(file.items[0] == .declaration);
    try std.testing.expect(file.items[1] == .component);
    try std.testing.expectEqualStrings("Hello", file.items[1].component.name);
}

test "parser handles HTML element with text content" {
    const source = "zempl Hello() { <div>Hello World</div> }";
    var lexer = Lexer.init(source, "test.zempl");

    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), file.items.len);
    try std.testing.expect(file.items[0] == .component);
    try std.testing.expectEqual(@as(usize, 1), file.items[0].component.body.len);
    try std.testing.expect(file.items[0].component.body[0] == .element);
    try std.testing.expectEqualStrings("div", file.items[0].component.body[0].element.tag_name);
    try std.testing.expectEqual(@as(usize, 1), file.items[0].component.body[0].element.children.len);
    try std.testing.expect(file.items[0].component.body[0].element.children[0] == .text);
}

test "parser handles expression interpolation" {
    const source = "zempl Hello() { <div>{name}</div> }";
    var lexer = Lexer.init(source, "test.zempl");

    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), file.items.len);
    try std.testing.expect(file.items[0] == .component);
    try std.testing.expect(file.items[0].component.body[0].element.children[0] == .expression);
    try std.testing.expectEqualStrings("name", file.items[0].component.body[0].element.children[0].expression.expr);
}

test "parser handles nested HTML elements" {
    const source = "zempl Hello() { <div><span>Nested</span></div> }";
    var lexer = Lexer.init(source, "test.zempl");

    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), file.items.len);
    try std.testing.expect(file.items[0].component.body[0].element.children[0] == .element);
    try std.testing.expectEqualStrings("span", file.items[0].component.body[0].element.children[0].element.tag_name);
}

test "parser handles void elements" {
    const source = "zempl Hello() { <div>Text<br/>More</div> }";
    var lexer = Lexer.init(source, "test.zempl");

    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), file.items.len);
    // The br element should be parsed as a child of div
    try std.testing.expect(file.items[0].component.body[0].element.children[1] == .element);
    try std.testing.expectEqualStrings("br", file.items[0].component.body[0].element.children[1].element.tag_name);
    try std.testing.expect(file.items[0].component.body[0].element.children[1].element.is_void);
}

test "parser handles HTML attributes" {
    const source = "zempl Hello() { <div class=\"test\" id={main}>Content</div> }";
    var lexer = Lexer.init(source, "test.zempl");

    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), file.items.len);
    // Attributes: class, test (value of class), id, main (value of id)
    try std.testing.expect(file.items[0].component.body[0].element.attributes.len >= 2);
    try std.testing.expectEqualStrings("class", file.items[0].component.body[0].element.attributes[0].name);
    try std.testing.expectEqualStrings("id", file.items[0].component.body[0].element.attributes[1].name);
}

// ============================================================================
// Unit Tests for Internal Parser Functions
// ============================================================================

test "isVoidElement recognizes all void tags" {
    try std.testing.expect(Parser.isVoidElement("br"));
    try std.testing.expect(Parser.isVoidElement("img"));
    try std.testing.expect(Parser.isVoidElement("input"));
    try std.testing.expect(Parser.isVoidElement("hr"));
    try std.testing.expect(Parser.isVoidElement("meta"));
    try std.testing.expect(Parser.isVoidElement("link"));
    try std.testing.expect(Parser.isVoidElement("area"));
    try std.testing.expect(Parser.isVoidElement("base"));
    try std.testing.expect(Parser.isVoidElement("col"));
    try std.testing.expect(Parser.isVoidElement("embed"));
    try std.testing.expect(Parser.isVoidElement("param"));
    try std.testing.expect(Parser.isVoidElement("source"));
    try std.testing.expect(Parser.isVoidElement("track"));
    try std.testing.expect(Parser.isVoidElement("wbr"));
}

test "isVoidElement returns false for non-void tags" {
    try std.testing.expect(!Parser.isVoidElement("div"));
    try std.testing.expect(!Parser.isVoidElement("span"));
    try std.testing.expect(!Parser.isVoidElement("p"));
    try std.testing.expect(!Parser.isVoidElement("html"));
}

test "parseComment handles basic comment" {
    const source = "zempl Test() { <div><!-- comment --></div> }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), file.items.len);
    try std.testing.expect(file.items[0].component.body[0].element.children[0] == .declaration);
}

test "parseComment handles comment without spaces" {
    const source = "zempl Test() { <div><!--asdf--></div> }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), file.items.len);
    try std.testing.expect(file.items[0].component.body[0].element.children[0] == .declaration);
}

test "parseComment handles multiline comment" {
    const source = "zempl Test() { <div><!-- multi\nline\ncomment --></div> }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), file.items.len);
    try std.testing.expect(file.items[0].component.body[0].element.children[0] == .declaration);
}

test "parseDoctype handles DOCTYPE html" {
    const source = "zempl Test() { <!DOCTYPE html><html></html> }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), file.items.len);
    try std.testing.expect(file.items[0].component.body[0] == .declaration);
}

test "parseDoctype handles lowercase doctype" {
    const source = "zempl Test() { <!doctype html><html></html> }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), file.items.len);
    try std.testing.expect(file.items[0].component.body[0] == .declaration);
}

test "parseCodeBlock handles simple code block" {
    const source = "zempl Test() { <div>@{ const x = 1; }</div> }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expect(file.items[0].component.body[0].element.children[0] == .code_block);
    try std.testing.expectEqualStrings(" const x = 1; ", file.items[0].component.body[0].element.children[0].code_block.statements);
}

test "parseCodeBlock handles multiline code block" {
    const source = "zempl Test() { <div>@{\n  const x = 1;\n  const y = 2;\n}</div> }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expect(file.items[0].component.body[0].element.children[0] == .code_block);
}

test "parseZemplConstruct handles @if statement" {
    const source = "zempl Test() { @if (true) { <span>Yes</span> } }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), file.items.len);
    try std.testing.expect(file.items[0].component.body[0] == .control_flow);
    try std.testing.expect(file.items[0].component.body[0].control_flow == .if_stmt);
}

test "parseZemplConstruct handles @if with else" {
    const source = "zempl Test() { @if (true) { <span>Yes</span> } @else { <span>No</span> } }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expect(file.items[0].component.body[0] == .control_flow);
    try std.testing.expect(file.items[0].component.body[0].control_flow.if_stmt.else_body != null);
}

test "parseZemplConstruct handles @for loop" {
    const source = "zempl Test() { @for (items) |item| { <li>{item}</li> } }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expect(file.items[0].component.body[0] == .control_flow);
    try std.testing.expect(file.items[0].component.body[0].control_flow == .for_loop);
}

test "parseZemplConstruct handles @while loop" {
    const source = "zempl Test() { @while (true) { <span>Loop</span> } }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expect(file.items[0].component.body[0] == .control_flow);
    try std.testing.expect(file.items[0].component.body[0].control_flow == .while_loop);
}

test "parseExpressionInterpolation handles simple expression" {
    const source = "zempl Test() { <div>{name}</div> }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expect(file.items[0].component.body[0].element.children[0] == .expression);
    try std.testing.expectEqualStrings("name", file.items[0].component.body[0].element.children[0].expression.expr);
}

test "parseExpressionInterpolation handles complex expression" {
    const source = "zempl Test() { <div>{user.name + \"test\"}</div> }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expect(file.items[0].component.body[0].element.children[0] == .expression);
    try std.testing.expect(file.items[0].component.body[0].element.children[0].expression.expr.len > 0);
}

test "parseExpressionInterpolation handles nested braces" {
    const source = "zempl Test() { <div>{if (true) { a } else { b }}</div> }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expect(file.items[0].component.body[0].element.children[0] == .expression);
}

test "parseTextContent handles plain text" {
    const source = "zempl Test() { <div>Hello World</div> }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expect(file.items[0].component.body[0].element.children[0] == .text);
    try std.testing.expectEqualStrings("Hello World", file.items[0].component.body[0].element.children[0].text.content);
}

test "parseTextContent handles text with special chars" {
    const source = "zempl Test() { <div>Hello &amp; World!</div> }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expect(file.items[0].component.body[0].element.children[0] == .text);
}

test "parseComponentCall handles component without args" {
    const source = "zempl Test() { @Header() }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expect(file.items[0].component.body[0] == .component_call);
    try std.testing.expectEqualStrings("Header", file.items[0].component.body[0].component_call.component_name);
    try std.testing.expectEqual(@as(usize, 0), file.items[0].component.body[0].component_call.args.len);
}

test "parseComponentCall handles component with args" {
    const source = "zempl Test() { @Button(\"Click\") }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expect(file.items[0].component.body[0] == .component_call);
    try std.testing.expectEqualStrings("Button", file.items[0].component.body[0].component_call.component_name);
}

test "parseComponentCall handles component with multiple args" {
    const source = "zempl Test() { @Card(\"Hello\", content) }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expect(file.items[0].component.body[0] == .component_call);
    try std.testing.expectEqualStrings("Card", file.items[0].component.body[0].component_call.component_name);
}

test "parseHtmlElementOrComment handles self-closing tag" {
    const source = "zempl Test() { <div><br/></div> }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expect(file.items[0].component.body[0].element.children[0] == .element);
    try std.testing.expect(file.items[0].component.body[0].element.children[0].element.is_void);
}

test "parseHtmlElementOrComment handles deep nesting" {
    const source = "zempl Test() { <div><p><span><strong>Deep</strong></span></p></div> }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expect(file.items[0].component.body[0].element.children[0].element.children[0].element.children[0] == .element);
}

test "parseElementStart handles element with boolean attribute" {
    const source = "zempl Test() { <input disabled> }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expect(file.items[0].component.body[0] == .element);
    try std.testing.expectEqualStrings("input", file.items[0].component.body[0].element.tag_name);
    try std.testing.expect(file.items[0].component.body[0].element.attributes.len == 1);
    try std.testing.expectEqualStrings("disabled", file.items[0].component.body[0].element.attributes[0].name);
    try std.testing.expectEqualStrings("true", file.items[0].component.body[0].element.attributes[0].value);
}

test "parseAttribute handles attribute with expression value" {
    const source = "zempl Test() { <div class={classes}>Content</div> }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expect(file.items[0].component.body[0] == .element);
}

test "parseZemplComponent fails without zempl keyword" {
    const source = "InvalidComponent() { }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");

    const result = parser.parseFile();
    try std.testing.expectError(error.ParseError, result);
}

test "parseZemplComponent fails without component name" {
    const source = "zempl () { }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");

    const result = parser.parseFile();
    try std.testing.expectError(error.ParseError, result);
}

test "parseZemplComponent fails without param list" {
    const source = "zempl Test { }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");

    const result = parser.parseFile();
    try std.testing.expectError(error.ParseError, result);
}

test "parseHtmlBody fails without opening brace" {
    const source = "zempl Test() <div>Content</div> }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");

    const result = parser.parseFile();
    try std.testing.expectError(error.ParseError, result);
}

test "parseHtmlBody fails with unclosed tag" {
    const source = "zempl Test() { <div>Content }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");

    const result = parser.parseFile();
    // The parser encounters '}' when expecting </div>, so it returns UnexpectedRBrace
    try std.testing.expectError(error.ParseError, result);
}
