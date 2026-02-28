const std = @import("std");
const ZemplFile = @import("ast.zig").ZemplFile;
const ZemplItem = @import("ast.zig").ZemplItem;
const ZemplComponent = @import("ast.zig").ZemplComponent;
const HtmlNode = @import("ast.zig").HtmlNode;
const HtmlElement = @import("ast.zig").HtmlElement;
const HtmlAttribute = @import("ast.zig").HtmlAttribute;
const ZemplArg = @import("ast.zig").ZemplArg;
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;
const TokenType = @import("lexer.zig").TokenType;
const zig_parse = @import("zig_parse.zig");
const Location = @import("error.zig").Location;

/// Parser errors
pub const ParserError = error{
    ExpectedZemplKeyword,
    ExpectedComponentName,
    ExpectedParamList,
    ExpectedLBrace,
    ExpectedRBrace,
    UnexpectedRBrace,
    UnexpectedEof,
    UnexpectedClosingTag,
    ExpectedTagName,
    ExpectedRAngle,
    ExpectedAttributeName,
    ExpectedExpression,
    UnclosedComment,
    ExpectedLParen,
    ExpectedIterator,
    ExpectedIn,
    UnknownZemplConstruct,
    UnexpectedToken,
    OutOfMemory,
};

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
    pub fn parseFile(self: *Parser) ParserError!ZemplFile {
        var items = std.ArrayList(ZemplItem).empty;
        errdefer {
            for (items.items) |item| {
                item.deinit(self.allocator);
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

            const parse_result = zig_parse.parseTopLevelItem(self.allocator, source_slice) catch {
                return error.UnexpectedToken;
            };
            if (parse_result) |result| {
                // Found a valid Zig declaration
                try items.append(self.allocator, .{ .declaration = result.source_text });

                // Advance lexer by consumed bytes
                self.lexer.advanceBy(result.consumed);
            } else {
                // Not a Zig declaration, try parsing as zempl component
                const component = try self.parseZemplComponent();
                try items.append(self.allocator, .{ .component = component });
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
    /// Handles both "zempl Name() {}" and "pub zempl Name() {}"
    fn parseZemplComponent(self: *Parser) ParserError!ZemplComponent {
        // Check for optional 'pub' keyword
        var is_public = false;
        const first_token = self.lexer.peek();
        if (first_token.token_type == .identifier and std.mem.eql(u8, first_token.text, "pub")) {
            _ = self.lexer.next(); // consume 'pub'
            is_public = true;
        }

        // Expect zempl keyword
        const zempl_token = self.lexer.next();
        if (zempl_token.token_type != .zempl_keyword) {
            return error.ExpectedZemplKeyword;
        }

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
        errdefer self.allocator.free(params_result.source_text);

        // Advance lexer by consumed bytes
        self.lexer.advanceBy(params_result.consumed);

        // Parse body (HTML content) - expects opening brace internally
        const body = try self.parseHtmlBody();

        return ZemplComponent{
            .name = name,
            .is_public = is_public,
            .params = params_result.source_text,
            .body = body,
            .location = name_token.location,
        };
    }

    /// Parse HTML body content
    /// Expects the opening brace to be the next token
    fn parseHtmlBody(self: *Parser) ParserError![]HtmlNode {
        // Expect opening brace
        const lbrace_token = self.lexer.next();
        if (lbrace_token.token_type != .lbrace) {
            return error.ExpectedLBrace;
        }

        var nodes = std.ArrayList(HtmlNode).empty;
        errdefer {
            for (nodes.items) |*node| {
                node.deinit(self.allocator);
            }
            nodes.deinit(self.allocator);
        }

        // Parse content until closing brace
        while (true) {
            const token = self.lexer.peek();
            switch (token.token_type) {
                .rbrace => {
                    _ = self.lexer.next(); // consume the brace
                    break;
                },
                .eof => return error.UnexpectedEof,
                .langle => {
                    const node = try self.parseHtmlElementOrComment();
                    try nodes.append(self.allocator, node);
                },
                .lbrace => {
                    const node = try self.parseExpressionInterpolation();
                    try nodes.append(self.allocator, node);
                },
                .identifier => {
                    if (std.mem.startsWith(u8, token.text, "@")) {
                        const node = try self.parseZemplConstruct();
                        try nodes.append(self.allocator, node);
                    } else {
                        // Regular text that happens to be an identifier
                        const node = try self.parseTextContent();
                        try nodes.append(self.allocator, node);
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
    fn parseHtmlElementOrComment(self: *Parser) ParserError!HtmlNode {
        _ = self.lexer.next(); // consume '<'

        // Check for comment or DOCTYPE
        const next_token = self.lexer.peek();
        if (next_token.token_type == .text) {
            if (std.mem.startsWith(u8, next_token.text, "!--")) {
                return self.parseComment();
            }
            if (std.mem.eql(u8, next_token.text, "!DOCTYPE") or std.mem.eql(u8, next_token.text, "!doctype")) {
                return self.parseDoctype();
            }
        }

        // Check for closing tag
        if (next_token.token_type == .slash) {
            _ = self.lexer.next(); // consume '/'
            return error.UnexpectedClosingTag;
        }

        // Parse opening tag
        return self.parseElementStart();
    }

    /// Parse HTML comment <!-- ... -->
    fn parseComment(self: *Parser) ParserError!HtmlNode {
        // Skip past <!--
        _ = self.lexer.next(); // consume the text token starting with "!--"

        // Read until -->
        const content_start = self.lexer.getPosition();
        var found_end = false;

        while (true) {
            const token = self.lexer.next();
            switch (token.token_type) {
                .text => {
                    if (std.mem.endsWith(u8, token.text, "--")) {
                        // Check if next token is >
                        const next = self.lexer.peek();
                        if (next.token_type == .rangle) {
                            _ = self.lexer.next(); // consume >
                            found_end = true;
                            break;
                        }
                    }
                },
                .rangle => {
                    // Check if previous text ended with --
                    found_end = true;
                    break;
                },
                .eof => return error.UnexpectedEof,
                else => {},
            }
        }

        if (!found_end) {
            return error.UnclosedComment;
        }

        const content_end = self.lexer.getPosition();
        const content = self.lexer.source[content_start..content_end];

        return HtmlNode{
            .comment = .{
                .content = try self.allocator.dupe(u8, content),
                .location = .{
                    .file_path = self.file_path,
                    .line = 1, // TODO: track line
                    .column = 1,
                },
            },
        };
    }

    /// Parse DOCTYPE declaration
    fn parseDoctype(self: *Parser) ParserError!HtmlNode {
        _ = self.lexer.next(); // consume !DOCTYPE or !doctype

        // Skip whitespace
        var token = self.lexer.next();

        // Read content until >
        const start_pos = self.lexer.getPosition();

        while (token.token_type != .rangle and token.token_type != .eof) {
            token = self.lexer.next();
        }

        if (token.token_type == .eof) {
            return error.UnexpectedEof;
        }

        const end_pos = self.lexer.getPosition();
        const content = self.lexer.source[start_pos..end_pos];

        return HtmlNode{ .doctype = .{
            .content = try self.allocator.dupe(u8, content),
            .location = .{
                .file_path = self.file_path,
                .line = 1,
                .column = 1,
            },
        } };
    }

    /// Parse element start tag and its content
    fn parseElementStart(self: *Parser) ParserError!HtmlNode {
        // Get tag name
        const tag_token = self.lexer.next();
        if (tag_token.token_type != .identifier) {
            return error.ExpectedTagName;
        }
        const tag_name = try self.allocator.dupe(u8, tag_token.text);
        errdefer self.allocator.free(tag_name);

        // Parse attributes
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
                    _ = self.lexer.next(); // skip unexpected token
                },
            }
        }

        // Check for self-closing tag or void element
        const is_void = isVoidElement(tag_name);
        var is_self_closing = false;

        const next_token = self.lexer.peek();
        if (next_token.token_type == .slash) {
            _ = self.lexer.next(); // consume '/'
            is_self_closing = true;
        }

        // Expect >
        const rangle_token = self.lexer.next();
        if (rangle_token.token_type != .rangle) {
            return error.ExpectedRAngle;
        }

        if (is_void or is_self_closing) {
            return HtmlNode{ .element = .{
                .tag_name = tag_name,
                .attributes = try attributes.toOwnedSlice(self.allocator),
                .children = &.{},
                .is_void = true,
                .location = tag_token.location,
            } };
        }

        // Parse children until closing tag
        var children = std.ArrayList(HtmlNode).empty;
        errdefer {
            for (children.items) |*child| {
                child.deinit(self.allocator);
            }
            children.deinit(self.allocator);
        }

        while (true) {
            const token = self.lexer.peek();

            // Check for closing tag
            if (token.token_type == .langle) {
                const saved_pos = self.lexer.getPosition();
                _ = self.lexer.next(); // consume '<'
                const slash_token = self.lexer.peek();
                if (slash_token.token_type == .slash) {
                    _ = self.lexer.next(); // consume '/'
                    const close_tag_token = self.lexer.next();
                    if (close_tag_token.token_type == .identifier and
                        std.mem.eql(u8, close_tag_token.text, tag_name))
                    {
                        // Found matching closing tag
                        const end_rangle = self.lexer.next();
                        if (end_rangle.token_type != .rangle) {
                            return error.ExpectedRAngle;
                        }
                        break;
                    } else {
                        // Not matching, push back and continue
                        // For now, treat as nested element
                        // TODO: handle mismatched tags better
                    }
                } else {
                    // Not a closing tag, parse as element
                    self.lexer.index = saved_pos; // restore position
                    const child = try self.parseHtmlElementOrComment();
                    try children.append(self.allocator, child);
                    continue;
                }
            }

            switch (token.token_type) {
                .eof => return error.UnexpectedEof,
                .rbrace => return error.UnexpectedRBrace,
                .langle => {
                    const child = try self.parseHtmlElementOrComment();
                    try children.append(self.allocator, child);
                },
                .lbrace => {
                    const child = try self.parseExpressionInterpolation();
                    try children.append(self.allocator, child);
                },
                .identifier => {
                    if (std.mem.startsWith(u8, token.text, "@")) {
                        const child = try self.parseZemplConstruct();
                        try children.append(self.allocator, child);
                    } else {
                        const child = try self.parseTextContent();
                        try children.append(self.allocator, child);
                    }
                },
                else => {
                    const child = try self.parseTextContent();
                    try children.append(self.allocator, child);
                },
            }
        }

        return HtmlNode{ .element = .{
            .tag_name = tag_name,
            .attributes = try attributes.toOwnedSlice(self.allocator),
            .children = try children.toOwnedSlice(self.allocator),
            .is_void = false,
            .location = tag_token.location,
        } };
    }

    /// Parse an HTML attribute
    fn parseAttribute(self: *Parser) ParserError!HtmlAttribute {
        const name_token = self.lexer.next();
        if (name_token.token_type != .identifier) {
            return error.ExpectedAttributeName;
        }
        const name = try self.allocator.dupe(u8, name_token.text);
        errdefer self.allocator.free(name);

        var value: []const u8 = "";

        // Check for =value
        const next_token = self.lexer.peek();
        if (next_token.token_type == .equal) {
            _ = self.lexer.next(); // consume '='

            const value_token = self.lexer.peek();
            if (value_token.token_type == .text or value_token.token_type == .identifier) {
                const val_token = self.lexer.next();
                value = try self.allocator.dupe(u8, val_token.text);
            } else if (value_token.token_type == .lbrace) {
                // Attribute value is a zempl expression
                const expr_node = try self.parseExpressionInterpolation();
                switch (expr_node) {
                    .expression => |expr| {
                        value = expr.expr; // Take ownership
                    },
                    else => return error.ExpectedExpression,
                }
            }
        }

        return HtmlAttribute{
            .name = name,
            .value = value,
            .location = name_token.location,
        };
    }

    /// Parse text content until special character
    fn parseTextContent(self: *Parser) ParserError!HtmlNode {
        const start_pos = self.lexer.getPosition();
        var end_pos = start_pos;

        while (true) {
            const token = self.lexer.peek();
            switch (token.token_type) {
                .langle, .rbrace, .eof, .lbrace => break,
                .identifier => {
                    if (std.mem.startsWith(u8, token.text, "@")) break;
                    _ = self.lexer.next();
                    end_pos = self.lexer.getPosition();
                },
                else => {
                    _ = self.lexer.next();
                    end_pos = self.lexer.getPosition();
                },
            }
        }

        const content = self.lexer.source[start_pos..end_pos];
        return HtmlNode{ .text = .{
            .content = try self.allocator.dupe(u8, content),
            .location = .{
                .file_path = self.file_path,
                .line = 1,
                .column = 1,
            },
        } };
    }

    /// Parse expression interpolation {expr}
    fn parseExpressionInterpolation(self: *Parser) ParserError!HtmlNode {
        const lbrace_token = self.lexer.next(); // consume '{'

        const start_pos = self.lexer.getPosition();

        // Find the matching }
        var brace_depth: i32 = 1;
        while (brace_depth > 0) {
            const token = self.lexer.next();
            switch (token.token_type) {
                .lbrace => brace_depth += 1,
                .rbrace => brace_depth -= 1,
                .eof => return error.UnexpectedEof,
                else => {},
            }
        }

        const end_pos = self.lexer.getPosition() - 1; // exclude the closing }
        const expr_text = self.lexer.source[start_pos..end_pos];

        return HtmlNode{ .expression = .{
            .expr = try self.allocator.dupe(u8, expr_text),
            .location = lbrace_token.location,
        } };
    }

    /// Parse zempl constructs (@if, @for, @while, @Component)
    fn parseZemplConstruct(self: *Parser) ParserError!HtmlNode {
        const at_token = self.lexer.next(); // consume '@identifier'
        const construct_name = at_token.text;

        if (std.mem.eql(u8, construct_name, "@if")) {
            return self.parseIfStatement();
        } else if (std.mem.eql(u8, construct_name, "@for")) {
            return self.parseForLoop();
        } else if (std.mem.eql(u8, construct_name, "@while")) {
            return self.parseWhileLoop();
        } else if (std.mem.eql(u8, construct_name, "@{")) {
            return self.parseCodeBlock();
        } else if (construct_name.len > 1 and std.ascii.isUpper(construct_name[1])) {
            // Component call: @ComponentName
            return self.parseComponentCall(construct_name);
        } else {
            return error.UnknownZemplConstruct;
        }
    }

    /// Parse @if statement
    fn parseIfStatement(self: *Parser) ParserError!HtmlNode {
        // Expect (condition)
        const lparen_token = self.lexer.next();
        if (lparen_token.token_type != .text or !std.mem.eql(u8, lparen_token.text, "(")) {
            return error.ExpectedLParen;
        }

        const cond_start = self.lexer.getPosition();

        // Find matching )
        var paren_depth: i32 = 1;
        while (paren_depth > 0) {
            const token = self.lexer.next();
            if (token.token_type == .text) {
                for (token.text) |c| {
                    if (c == '(') paren_depth += 1;
                    if (c == ')') paren_depth -= 1;
                }
            } else if (token.token_type == .eof) {
                return error.UnexpectedEof;
            }
        }

        const cond_end = self.lexer.getPosition() - 1;
        const condition = try self.allocator.dupe(u8, self.lexer.source[cond_start..cond_end]);
        errdefer self.allocator.free(condition);

        // Expect { then_body }
        const then_body = try self.parseHtmlBody();
        errdefer {
            for (then_body) |*node| {
                node.deinit(self.allocator);
            }
            self.allocator.free(then_body);
        }

        // Check for @else
        var else_body: ?[]HtmlNode = null;
        const next_token = self.lexer.peek();
        if (next_token.token_type == .identifier and std.mem.eql(u8, next_token.text, "@else")) {
            _ = self.lexer.next(); // consume @else
            else_body = try self.parseHtmlBody();
        }

        return HtmlNode{ .control_flow = .{ .if_stmt = .{
            .condition = condition,
            .then_body = then_body,
            .else_body = else_body,
            .location = .{
                .file_path = self.file_path,
                .line = 1,
                .column = 1,
            },
        } } };
    }

    /// Parse @for loop
    fn parseForLoop(self: *Parser) ParserError!HtmlNode {
        // Parse (iterator in iterable)
        const lparen_token = self.lexer.next();
        if (lparen_token.token_type != .text or !std.mem.eql(u8, lparen_token.text, "(")) {
            return error.ExpectedLParen;
        }

        // Get iterator variable
        const iter_token = self.lexer.next();
        if (iter_token.token_type != .identifier) {
            return error.ExpectedIterator;
        }
        const iterator_var = try self.allocator.dupe(u8, iter_token.text);
        errdefer self.allocator.free(iterator_var);

        // Expect 'in'
        const in_token = self.lexer.next();
        if (in_token.token_type != .identifier or !std.mem.eql(u8, in_token.text, "in")) {
            return error.ExpectedIn;
        }

        // Get iterable expression
        const iterable_start = self.lexer.getPosition();

        var paren_depth: i32 = 1;
        while (paren_depth > 0) {
            const token = self.lexer.next();
            if (token.token_type == .text) {
                for (token.text) |c| {
                    if (c == '(') paren_depth += 1;
                    if (c == ')') paren_depth -= 1;
                }
            } else if (token.token_type == .eof) {
                return error.UnexpectedEof;
            }
        }

        const iterable_end = self.lexer.getPosition() - 1;
        const iterable = try self.allocator.dupe(u8, self.lexer.source[iterable_start..iterable_end]);
        errdefer self.allocator.free(iterable);

        // Parse body
        const body = try self.parseHtmlBody();

        return HtmlNode{ .control_flow = .{ .for_loop = .{
            .iterator_var = iterator_var,
            .iterable = iterable,
            .body = body,
            .location = .{
                .file_path = self.file_path,
                .line = 1,
                .column = 1,
            },
        } } };
    }

    /// Parse @while loop
    fn parseWhileLoop(self: *Parser) ParserError!HtmlNode {
        // Parse (condition)
        const lparen_token = self.lexer.next();
        if (lparen_token.token_type != .text or !std.mem.eql(u8, lparen_token.text, "(")) {
            return error.ExpectedLParen;
        }

        const cond_start = self.lexer.getPosition();

        var paren_depth: i32 = 1;
        while (paren_depth > 0) {
            const token = self.lexer.next();
            if (token.token_type == .text) {
                for (token.text) |c| {
                    if (c == '(') paren_depth += 1;
                    if (c == ')') paren_depth -= 1;
                }
            } else if (token.token_type == .eof) {
                return error.UnexpectedEof;
            }
        }

        const cond_end = self.lexer.getPosition() - 1;
        const condition = try self.allocator.dupe(u8, self.lexer.source[cond_start..cond_end]);

        // Parse body
        const body = try self.parseHtmlBody();

        return HtmlNode{ .control_flow = .{ .while_loop = .{
            .condition = condition,
            .capture = null,
            .body = body,
            .location = .{
                .file_path = self.file_path,
                .line = 1,
                .column = 1,
            },
        } } };
    }

    /// Parse @{...} code block
    fn parseCodeBlock(self: *Parser) ParserError!HtmlNode {
        const at_lbrace_token = self.lexer.next(); // consume '@{'

        const start_pos = self.lexer.getPosition();

        // Find matching }
        var brace_depth: i32 = 1;
        while (brace_depth > 0) {
            const token = self.lexer.next();
            switch (token.token_type) {
                .lbrace => brace_depth += 1,
                .rbrace => brace_depth -= 1,
                .eof => return error.UnexpectedEof,
                else => {},
            }
        }

        const end_pos = self.lexer.getPosition() - 1;
        const statements = self.lexer.source[start_pos..end_pos];

        return HtmlNode{ .code_block = .{
            .statements = try self.allocator.dupe(u8, statements),
            .location = at_lbrace_token.location,
        } };
    }

    /// Parse @Component(...) call
    fn parseComponentCall(self: *Parser, component_name: []const u8) ParserError!HtmlNode {
        const name = try self.allocator.dupe(u8, component_name[1..]); // remove @ prefix
        errdefer self.allocator.free(name);

        var args = std.ArrayList(ZemplArg).empty;
        errdefer {
            for (args.items) |arg| {
                arg.deinit(self.allocator);
            }
            args.deinit(self.allocator);
        }

        // Check for arguments
        const next_token = self.lexer.peek();
        if (next_token.token_type == .text and std.mem.eql(u8, next_token.text, "(")) {
            _ = self.lexer.next(); // consume '('

            // Parse argument expressions separated by commas
            while (true) {
                const token = self.lexer.peek();
                if (token.token_type == .text and std.mem.eql(u8, token.text, ")")) {
                    _ = self.lexer.next(); // consume ')'
                    break;
                }

                if (token.token_type == .eof) {
                    return error.UnexpectedEof;
                }

                // Parse argument expression
                const arg_start = self.lexer.getPosition();

                var paren_depth: i32 = 1;
                while (paren_depth > 0) {
                    const arg_token = self.lexer.next();
                    if (arg_token.token_type == .text) {
                        for (arg_token.text) |c| {
                            if (c == '(') paren_depth += 1;
                            if (c == ')') paren_depth -= 1;
                        }
                    }
                    if (paren_depth == 1 and arg_token.token_type == .text and std.mem.eql(u8, arg_token.text, ",")) {
                        break;
                    }
                    if (arg_token.token_type == .eof) {
                        return error.UnexpectedEof;
                    }
                }

                const arg_end = self.lexer.getPosition();
                var arg_text = self.lexer.source[arg_start..arg_end];

                // Remove trailing comma if present
                if (std.mem.endsWith(u8, arg_text, ",")) {
                    arg_text = arg_text[0 .. arg_text.len - 1];
                }

                const arg_expr = try self.allocator.dupe(u8, arg_text);
                try args.append(self.allocator, .{
                    .expr = arg_expr,
                    .location = .{
                        .file_path = self.file_path,
                        .line = 1,
                        .column = 1,
                    },
                });

                if (paren_depth == 0) {
                    break;
                }
            }
        }

        return HtmlNode{ .component_call = .{
            .component_name = name,
            .args = try args.toOwnedSlice(self.allocator),
            .location = .{
                .file_path = self.file_path,
                .line = 1,
                .column = 1,
            },
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
    const source = "zempl Hello() { <div class=\"test\" id=main>Content</div> }";
    var lexer = Lexer.init(source, "test.zempl");

    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), file.items.len);
    // Attributes: class, test (value of class), id, main (value of id)
    try std.testing.expect(file.items[0].component.body[0].element.attributes.len >= 2);
    try std.testing.expectEqualStrings("class", file.items[0].component.body[0].element.attributes[0].name);
    try std.testing.expectEqualStrings("id", file.items[0].component.body[0].element.attributes[2].name);
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
    const source = "zempl Test() { @Header }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expect(file.items[0].component.body[0] == .component_call);
    try std.testing.expectEqualStrings("Header", file.items[0].component.body[0].component_call.component_name);
    try std.testing.expectEqual(@as(usize, 0), file.items[0].component.body[0].component_call.args.len);
}

test "parseComponentCall handles component with args" {
    const source = "zempl Test() { @Button(text: \"Click\") }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");
    const file = try parser.parseFile();
    defer file.deinit(std.testing.allocator);

    try std.testing.expect(file.items[0].component.body[0] == .component_call);
    try std.testing.expectEqualStrings("Button", file.items[0].component.body[0].component_call.component_name);
}

test "parseComponentCall handles component with multiple args" {
    const source = "zempl Test() { @Card(title: \"Hello\", body: content) }";
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
    try std.testing.expectError(error.ExpectedZemplKeyword, result);
}

test "parseZemplComponent fails without component name" {
    const source = "zempl () { }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");

    const result = parser.parseFile();
    try std.testing.expectError(error.ExpectedComponentName, result);
}

test "parseZemplComponent fails without param list" {
    const source = "zempl Test { }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");

    const result = parser.parseFile();
    try std.testing.expectError(error.ExpectedParamList, result);
}

test "parseHtmlBody fails without opening brace" {
    const source = "zempl Test() <div>Content</div> }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");

    const result = parser.parseFile();
    try std.testing.expectError(error.ExpectedLBrace, result);
}

test "parseHtmlBody fails with unclosed tag" {
    const source = "zempl Test() { <div>Content }";
    var lexer = Lexer.init(source, "test.zempl");
    var parser = Parser.init(&lexer, std.testing.allocator, "test.zempl");

    const result = parser.parseFile();
    // The parser encounters '}' when expecting </div>, so it returns UnexpectedRBrace
    try std.testing.expectError(error.UnexpectedRBrace, result);
}
