const std = @import("std");

pub const Location = struct {
    file_path: []const u8,
    row: usize,
    row_start: usize,
    index: usize,

    pub fn format(
        self: Location,
        writer: anytype,
    ) !void {
        const column = self.index - self.row_start + 1;
        try writer.print("{s}:{d}:{d}", .{ self.file_path, self.row, column });
    }
};

/// Token types for the zempl lexer
pub const TokenType = enum {
    // Special tokens
    eof,
    invalid, // Unknown/invalid character

    // Content tokens
    identifier,
    string,
    text,

    // Zempl-specific keywords and symbols
    at_lbrace, // @{ - code block start
    lbrace, // { - expression interpolation start
    rbrace, // } - expression interpolation end
    lparen, // (
    rparen, // )
    pipe, // |
    comma, // ,
    semicolon, // ;

    // HTML tokens
    langle, // <
    rangle, // >
    slash, // / (used in end tags </ and self-closing />)
    equal, // =
    bang, // ! (used for comments and doctype declarations)
};

/// A token with its type, location in source, and text content
pub const Token = struct {
    token_type: TokenType,
    location: Location,
    text: []const u8,

    pub fn init(token_type: TokenType, location: Location, text: []const u8) Token {
        return .{
            .token_type = token_type,
            .location = location,
            .text = text,
        };
    }
};

/// Lexer for zempl template files
pub const Lexer = struct {
    source: [:0]const u8,
    file_path: []const u8,
    index: usize,
    row: usize,
    row_start: usize,

    pub fn init(source: [:0]const u8, file_path: []const u8) Lexer {
        return .{
            .source = source,
            .file_path = file_path,
            .index = 0,
            .row = 1,
            .row_start = 0,
        };
    }

    /// Get current position in source
    pub fn getPosition(self: Lexer) usize {
        return self.index;
    }

    /// Get current location (line and column)
    pub fn getLocation(self: Lexer) Location {
        return .{
            .file_path = self.file_path,
            .row = self.row,
            .row_start = self.row_start,
            .index = self.index,
        };
    }

    /// Advance position by count bytes, updating line and column tracking
    pub fn advanceBy(self: *Lexer, count: usize) void {
        var remaining: usize = count;
        while (remaining > 0) : (remaining -= 1) {
            _ = self.advance();
        }
    }

    /// Peek at current character without consuming
    fn peekChar(self: Lexer) ?u8 {
        if (self.index >= self.source.len) {
            return null;
        }
        return self.source[self.index];
    }

    /// Peek at next character without consuming
    fn peekCharAhead(self: Lexer, ahead: usize) ?u8 {
        const pos = self.index + ahead;
        if (pos >= self.source.len) {
            return null;
        }
        return self.source[pos];
    }

    /// Consume current character and advance, tracking line and column
    fn advance(self: *Lexer) ?u8 {
        if (self.index >= self.source.len) {
            return null;
        }
        const ch = self.source[self.index];
        self.index += 1;

        // Update line and column
        if (ch == '\n') {
            self.row += 1;
            self.row_start = self.index;
        }

        return ch;
    }

    /// Skip whitespace characters
    fn skipWhitespace(self: *Lexer) void {
        while (true) {
            const ch = self.peekChar() orelse break;
            if (std.ascii.isWhitespace(ch)) {
                _ = self.advance();
            } else {
                break;
            }
        }
    }

    /// Check if character is valid identifier start (letter, underscore, or @)
    fn isIdentifierStart(ch: u8) bool {
        return std.ascii.isAlphabetic(ch) or ch == '_' or ch == '@';
    }

    /// Check if character is valid identifier continuation (alphanumeric, underscore, or dash)
    fn isIdentifierPart(ch: u8) bool {
        return std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-';
    }

    /// Scan an identifier
    fn scanIdentifier(self: *Lexer) Token {
        const location = self.getLocation();
        const start = self.index;

        // Consume first character (already validated as identifier start)
        _ = self.advance();

        // Consume rest of identifier
        while (true) {
            const ch = self.peekChar() orelse break;
            if (isIdentifierPart(ch)) {
                _ = self.advance();
            } else {
                break;
            }
        }

        const text = self.source[start..self.index];
        return Token.init(.identifier, location, text);
    }

    /// Scan a string literal
    fn scanString(self: *Lexer) Token {
        const location = self.getLocation();
        const start = self.index;

        // Consume first character (already validated as identifier start)
        _ = self.advance();

        // Consume rest of identifier
        while (self.advance()) |ch| {
            if (ch == '"')
                break;
        }

        const text = self.source[start..self.index];
        return Token.init(.string, location, text);
    }

    /// Get next token (general purpose - for tags, attributes, etc.)
    pub fn next(self: *Lexer) Token {
        self.skipWhitespace();

        const location = self.getLocation();
        const start = self.index;
        const ch = self.peekChar();

        if (ch == null) {
            return Token.init(.eof, location, "");
        }

        const c = ch.?;

        // Check for HTML tokens
        if (c == '<') {
            _ = self.advance();
            return Token.init(.langle, location, "<");
        }

        if (c == '>') {
            _ = self.advance();
            return Token.init(.rangle, location, ">");
        }

        if (c == '/') {
            _ = self.advance();
            return Token.init(.slash, location, "/");
        }

        if (c == '=') {
            _ = self.advance();
            return Token.init(.equal, location, "=");
        }

        // Check for zempl tokens
        if (c == '{') {
            _ = self.advance();
            return Token.init(.lbrace, location, "{");
        }

        if (c == '}') {
            _ = self.advance();
            return Token.init(.rbrace, location, "}");
        }

        if (c == '(') {
            _ = self.advance();
            return Token.init(.lparen, location, "(");
        }

        if (c == ')') {
            _ = self.advance();
            return Token.init(.rparen, location, ")");
        }

        if (c == '|') {
            _ = self.advance();
            return Token.init(.pipe, location, "|");
        }

        if (c == ',') {
            _ = self.advance();
            return Token.init(.comma, location, ",");
        }

        if (c == ';') {
            _ = self.advance();
            return Token.init(.semicolon, location, ";");
        }

        if (c == '!') {
            _ = self.advance();
            return Token.init(.bang, location, "!");
        }

        // Check for @{
        if (c == '@') {
            if (self.peekCharAhead(1) == '{') {
                _ = self.advance(); // consume '@'
                _ = self.advance(); // consume '{'
                return Token.init(.at_lbrace, location, self.source[start..self.index]);
            }
            // Otherwise it's an identifier starting with @
            return self.scanIdentifier();
        }

        // Check for "
        if (c == '"') {
            return self.scanString();
        }

        // Identifier
        if (isIdentifierStart(c)) {
            return self.scanIdentifier();
        }

        // Unknown character - return invalid token with the character
        _ = self.advance();
        return Token.init(.invalid, location, self.source[start..self.index]);
    }

    pub fn nextContent(self: *Lexer) Token {
        self.skipWhitespace();
        const location = self.getLocation();
        const start = self.index;
        if (start == self.source.len) {
            return Token.init(.eof, location, "");
        }
        while (self.peekChar()) |ch| {
            switch (ch) {
                '<', '>', '{', '}', '@' => break,
                else => {},
            }
            _ = self.advance();
        }
        var text = self.source[start..self.index];
        text = std.mem.trimEnd(u8, text, &std.ascii.whitespace);
        return Token.init(.text, location, text);
    }

    pub fn peek(self: *Lexer) Token {
        const saved_index = self.index;
        const saved_row = self.row;
        const saved_row_start = self.row_start;
        const token = self.next();
        self.index = saved_index;
        self.row = saved_row;
        self.row_start = saved_row_start;
        return token;
    }

    pub fn peekContent(self: *Lexer) Token {
        const saved_index = self.index;
        const saved_row = self.row;
        const saved_row_start = self.row_start;
        const token = self.nextContent();
        self.index = saved_index;
        self.row = saved_row;
        self.row_start = saved_row_start;
        return token;
    }
};

// Tests
test "Lexer initialization" {
    const source = "hello";
    var lexer = Lexer.init(source, "test.zempl");

    try std.testing.expectEqual(@as(usize, 0), lexer.getPosition());
}

test "EOF token" {
    const source = "";
    var lexer = Lexer.init(source, "test.zempl");

    const token = lexer.next();
    try std.testing.expectEqual(TokenType.eof, token.token_type);
}

test "Identifier token" {
    const source = "div";
    var lexer = Lexer.init(source, "test.zempl");

    const token = lexer.next();
    try std.testing.expectEqual(TokenType.identifier, token.token_type);
    try std.testing.expectEqualStrings("div", token.text);
}

test "Identifier with @" {
    const source = "@if";
    var lexer = Lexer.init(source, "test.zempl");

    const token = lexer.next();
    try std.testing.expectEqual(TokenType.identifier, token.token_type);
    try std.testing.expectEqualStrings("@if", token.text);
}

test "HTML tokens" {
    const source = "< > = /";
    var lexer = Lexer.init(source, "test.zempl");

    var token = lexer.next();
    try std.testing.expectEqual(TokenType.langle, token.token_type);

    token = lexer.next();
    try std.testing.expectEqual(TokenType.rangle, token.token_type);

    token = lexer.next();
    try std.testing.expectEqual(TokenType.equal, token.token_type);

    token = lexer.next();
    try std.testing.expectEqual(TokenType.slash, token.token_type);
}

test "End tag tokens" {
    const source = "</div>";
    var lexer = Lexer.init(source, "test.zempl");

    var token = lexer.next();
    try std.testing.expectEqual(TokenType.langle, token.token_type);
    try std.testing.expectEqualStrings("<", token.text);

    token = lexer.next();
    try std.testing.expectEqual(TokenType.slash, token.token_type);
    try std.testing.expectEqualStrings("/", token.text);

    token = lexer.next();
    try std.testing.expectEqual(TokenType.identifier, token.token_type);
    try std.testing.expectEqualStrings("div", token.text);

    token = lexer.next();
    try std.testing.expectEqual(TokenType.rangle, token.token_type);
    try std.testing.expectEqualStrings(">", token.text);
}

test "Slash token" {
    const source = "/>";
    var lexer = Lexer.init(source, "test.zempl");

    var token = lexer.next();
    try std.testing.expectEqual(TokenType.slash, token.token_type);
    try std.testing.expectEqualStrings("/", token.text);

    token = lexer.next();
    try std.testing.expectEqual(TokenType.rangle, token.token_type);
    try std.testing.expectEqualStrings(">", token.text);
}

test "Zempl braces" {
    const source = "{}";
    var lexer = Lexer.init(source, "test.zempl");

    var token = lexer.next();
    try std.testing.expectEqual(TokenType.lbrace, token.token_type);

    token = lexer.next();
    try std.testing.expectEqual(TokenType.rbrace, token.token_type);
}

test "Code block start" {
    const source = "@{";
    var lexer = Lexer.init(source, "test.zempl");

    const token = lexer.next();
    try std.testing.expectEqual(TokenType.at_lbrace, token.token_type);
    try std.testing.expectEqualStrings("@{", token.text);
}

test "Text content" {
    const source = "Hello world";
    var lexer = Lexer.init(source, "test.zempl");

    const token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("Hello world", token.text);
}

test "Text content stops at special char" {
    const source = "Hello <world>";
    var lexer = Lexer.init(source, "test.zempl");

    // First call returns text until <
    var token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("Hello", token.text);

    // At <, returns empty text to indicate delimiter
    token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("", token.text);
}

test "Text content with interpolation" {
    const source = "Hello {name}!";
    var lexer = Lexer.init(source, "test.zempl");

    var token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("Hello", token.text);

    // At {, returns empty text to indicate delimiter
    token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("", token.text);
}

test "Peek doesn't advance" {
    const source = "div";
    var lexer = Lexer.init(source, "test.zempl");

    const token1 = lexer.peek();
    try std.testing.expectEqual(TokenType.identifier, token1.token_type);

    const token2 = lexer.next();
    try std.testing.expectEqual(TokenType.identifier, token2.token_type);
    try std.testing.expectEqualStrings("div", token2.text);
}

test "Complex zempl snippet" {
    const source = "<h1>{title}</h1>";
    var lexer = Lexer.init(source, "test.zempl");

    // In tag context
    var token = lexer.next();
    try std.testing.expectEqual(TokenType.langle, token.token_type);

    token = lexer.next();
    try std.testing.expectEqual(TokenType.identifier, token.token_type);
    try std.testing.expectEqualStrings("h1", token.text);

    token = lexer.next();
    try std.testing.expectEqual(TokenType.rangle, token.token_type);

    // Switch to content context
    // At {, nextContent() returns empty text to indicate delimiter
    token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("", token.text);

    // The expression {title} would be handled by expression parser
}

test "Invalid token" {
    const source = "div $";
    var lexer = Lexer.init(source, "test.zempl");

    // First token is valid identifier
    var token = lexer.next();
    try std.testing.expectEqual(TokenType.identifier, token.token_type);
    try std.testing.expectEqualStrings("div", token.text);

    // Second token is invalid (the $ character)
    token = lexer.next();
    try std.testing.expectEqual(TokenType.invalid, token.token_type);
    try std.testing.expectEqualStrings("$", token.text);
    try std.testing.expectEqual(@as(usize, 1), token.location.row);
    try std.testing.expectEqual(@as(usize, 0), token.location.row_start);
    try std.testing.expectEqual(@as(usize, 4), token.location.index);
}

test "Line and column tracking" {
    const source = "div\nspan";
    var lexer = Lexer.init(source, "test.zempl");

    var token = lexer.next();
    try std.testing.expectEqual(TokenType.identifier, token.token_type);
    try std.testing.expectEqualStrings("div", token.text);
    try std.testing.expectEqual(@as(usize, 1), token.location.row);
    try std.testing.expectEqual(@as(usize, 0), token.location.row_start);
    try std.testing.expectEqual(@as(usize, 0), token.location.index);

    token = lexer.next();
    try std.testing.expectEqual(TokenType.identifier, token.token_type);
    try std.testing.expectEqualStrings("span", token.text);
    try std.testing.expectEqual(@as(usize, 2), token.location.row);
    try std.testing.expectEqual(@as(usize, 4), token.location.row_start);
    try std.testing.expectEqual(@as(usize, 4), token.location.index);
}

test "HTML tag with dash" {
    const source = "<my-custom-element>content</my-custom-element>";
    var lexer = Lexer.init(source, "test.zempl");

    var token = lexer.next();
    try std.testing.expectEqual(TokenType.langle, token.token_type);

    token = lexer.next();
    try std.testing.expectEqual(TokenType.identifier, token.token_type);
    try std.testing.expectEqualStrings("my-custom-element", token.text);

    token = lexer.next();
    try std.testing.expectEqual(TokenType.rangle, token.token_type);
}

test "Attribute with dash" {
    const source = "data-value";
    var lexer = Lexer.init(source, "test.zempl");

    const token = lexer.next();
    try std.testing.expectEqual(TokenType.identifier, token.token_type);
    try std.testing.expectEqualStrings("data-value", token.text);
}

// ============================================================================
// Comprehensive nextContent() tests
// ============================================================================

test "nextContent returns text until <" {
    const source = "Hello <div>";
    var lexer = Lexer.init(source, "test.zempl");

    var token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("Hello", token.text);

    // At <, returns empty text to indicate delimiter
    token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("", token.text);
}

test "nextContent returns text until {" {
    const source = "Hello {name}";
    var lexer = Lexer.init(source, "test.zempl");

    var token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("Hello", token.text);

    // At {, returns empty text to indicate delimiter
    token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("", token.text);
}

test "nextContent returns text until @identifier" {
    const source = "Hello @if(true)";
    var lexer = Lexer.init(source, "test.zempl");

    var token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("Hello", token.text);

    // At @, returns empty text to indicate delimiter
    token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("", token.text);
}

test "nextContent returns @ as empty text token" {
    const source = "Hello @{";
    var lexer = Lexer.init(source, "test.zempl");

    var token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("Hello", token.text);

    // At @, returns empty text to indicate delimiter
    token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("", token.text);
}

test "nextContent handles empty string" {
    const source = "";
    var lexer = Lexer.init(source, "test.zempl");

    const token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.eof, token.token_type);
}

test "nextContent handles only whitespace" {
    const source = "   ";
    var lexer = Lexer.init(source, "test.zempl");

    const token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.eof, token.token_type);
}

test "nextContent handles HTML entities like &amp;" {
    const source = "Hello &amp; World";
    var lexer = Lexer.init(source, "test.zempl");

    const token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("Hello &amp; World", token.text);
}

test "nextContent handles consecutive special chars" {
    // nextContent() returns empty text when at special chars, without consuming them
    const source = "<div>";
    var lexer = Lexer.init(source, "test.zempl");

    // At <, returns empty text (position stays at <)
    var token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("", token.text);

    // Still at <, returns empty text again (caller must use next() to consume <)
    token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("", token.text);
}

test "nextContent handles text after special char" {
    const source = "Text{content}";
    var lexer = Lexer.init(source, "test.zempl");

    // Text until {
    var token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("Text", token.text);

    // At {, returns empty text
    token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("", token.text);

    // Still at {, returns empty text again
    token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("", token.text);
}

test "nextContent handles HTML comment start" {
    const source = "<!-- comment -->";
    var lexer = Lexer.init(source, "test.zempl");

    // At <, returns empty text
    const token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("", token.text);
}

test "nextContent handles text before HTML comment" {
    const source = "Text <!-- comment -->";
    var lexer = Lexer.init(source, "test.zempl");

    var token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("Text", token.text);

    // At <, returns empty text
    token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("", token.text);
}

test "nextContent sequences correctly through mixed content" {
    const source = "Hello <b>{name}";
    var lexer = Lexer.init(source, "test.zempl");

    // Hello␣ (text until <)
    var token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("Hello", token.text);

    // At <, returns empty text (caller must use next() to consume)
    token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("", token.text);
}

test "nextContent handles multiline text" {
    const source = "Line1\nLine2\nLine3";
    var lexer = Lexer.init(source, "test.zempl");

    const token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("Line1\nLine2\nLine3", token.text);
}

test "nextContent handles text with parentheses" {
    const source = "Hello (world)";
    var lexer = Lexer.init(source, "test.zempl");

    const token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("Hello (world)", token.text);
}

test "nextContent handles text with semicolons" {
    const source = "a; b; c;";
    var lexer = Lexer.init(source, "test.zempl");

    const token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("a; b; c;", token.text);
}

test "nextContent handles text with exclamation" {
    const source = "Hello!";
    var lexer = Lexer.init(source, "test.zempl");

    const token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("Hello!", token.text);
}

test "peekContent does not advance lexer" {
    const source = "Hello <div>";
    var lexer = Lexer.init(source, "test.zempl");

    // peekContent should return the same as nextContent but not advance
    const peek1 = lexer.peekContent();
    try std.testing.expectEqual(TokenType.text, peek1.token_type);
    try std.testing.expectEqualStrings("Hello", peek1.text);

    // Position should be unchanged
    const peek2 = lexer.peekContent();
    try std.testing.expectEqual(TokenType.text, peek2.token_type);
    try std.testing.expectEqualStrings("Hello", peek2.text);

    // Now actually consume it
    const token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("Hello", token.text);

    // Next should be empty text (delimiter at <)
    const peek3 = lexer.peekContent();
    try std.testing.expectEqual(TokenType.text, peek3.token_type);
    try std.testing.expectEqualStrings("", peek3.text);
}
