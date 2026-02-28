const std = @import("std");
const Location = @import("error.zig").Location;

/// Token types for the zempl lexer
pub const TokenType = enum {
    // Special tokens
    eof,
    invalid, // Unknown/invalid character

    // Content tokens
    identifier,
    text,

    // Zempl-specific keywords and symbols
    zempl_keyword,
    at_lbrace, // @{ - code block start
    lbrace, // { - expression interpolation start
    rbrace, // } - expression interpolation end

    // HTML tokens
    langle, // <
    rangle, // >
    slash, // / (used in end tags </ and self-closing />)
    equal, // =
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
    line: usize,
    column: usize,

    pub fn init(source: [:0]const u8, file_path: []const u8) Lexer {
        return .{
            .source = source,
            .file_path = file_path,
            .index = 0,
            .line = 1,
            .column = 1,
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
            .line = self.line,
            .column = self.column,
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
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }

        return ch;
    }

    /// Skip whitespace characters
    fn skipWhitespace(self: *Lexer) void {
        while (true) {
            const ch = self.peekChar() orelse break;
            if (ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r') {
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

        // Check for keywords
        if (std.mem.eql(u8, text, "zempl")) {
            return Token.init(.zempl_keyword, location, text);
        }

        return Token.init(.identifier, location, text);
    }

    /// Scan text content until we hit a special character
    fn scanText(self: *Lexer) Token {
        const location = self.getLocation();
        const start = self.index;

        while (true) {
            const ch = self.peekChar() orelse break;

            // Check for special characters that end text content
            if (ch == '<') {
                // Check for </ (end tag)
                if (self.peekCharAhead(1) == '/') {
                    break;
                }
                break;
            }

            if (ch == '{' or ch == '@') {
                break;
            }

            _ = self.advance();
        }

        const text = self.source[start..self.index];
        return Token.init(.text, location, text);
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

        // Identifier
        if (isIdentifierStart(c)) {
            return self.scanIdentifier();
        }

        // Unknown character - return invalid token with the character
        _ = self.advance();
        return Token.init(.invalid, location, self.source[start..self.index]);
    }

    /// Get next token in content context (returns text until special char)
    pub fn nextContent(self: *Lexer) Token {
        self.skipWhitespace();

        const location = self.getLocation();
        const start = self.index;
        const ch = self.peekChar();

        if (ch == null) {
            return Token.init(.eof, location, "");
        }

        const c = ch.?;

        // If we're at a special character, return it as a token
        if (c == '<') {
            _ = self.advance();
            return Token.init(.langle, location, "<");
        }

        if (c == '{') {
            _ = self.advance();
            return Token.init(.lbrace, location, "{");
        }

        if (c == '@') {
            // Check for @{
            if (self.peekCharAhead(1) == '{') {
                _ = self.advance(); // consume '@'
                _ = self.advance(); // consume '{'
                return Token.init(.at_lbrace, location, self.source[start..self.index]);
            }
            // It's an @identifier
            return self.scanIdentifier();
        }

        // Otherwise scan text content
        return self.scanText();
    }

    /// Look at next token without consuming (uses next() method)
    pub fn peek(self: *Lexer) Token {
        const saved_index = self.index;
        const saved_line = self.line;
        const saved_column = self.column;
        const token = self.next();
        self.index = saved_index;
        self.line = saved_line;
        self.column = saved_column;
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

test "Zempl keyword" {
    const source = "zempl";
    var lexer = Lexer.init(source, "test.zempl");

    const token = lexer.next();
    try std.testing.expectEqual(TokenType.zempl_keyword, token.token_type);
    try std.testing.expectEqualStrings("zempl", token.text);
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

    var token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("Hello ", token.text);

    token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.langle, token.token_type);
}

test "Text content with interpolation" {
    const source = "Hello {name}!";
    var lexer = Lexer.init(source, "test.zempl");

    var token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.text, token.token_type);
    try std.testing.expectEqualStrings("Hello ", token.text);

    token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.lbrace, token.token_type);
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
    token = lexer.nextContent();
    try std.testing.expectEqual(TokenType.lbrace, token.token_type);

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
    try std.testing.expectEqual(@as(usize, 1), token.location.line);
    try std.testing.expectEqual(@as(usize, 5), token.location.column);
}

test "Line and column tracking" {
    const source = "div\nspan";
    var lexer = Lexer.init(source, "test.zempl");

    var token = lexer.next();
    try std.testing.expectEqual(TokenType.identifier, token.token_type);
    try std.testing.expectEqualStrings("div", token.text);
    try std.testing.expectEqual(@as(usize, 1), token.location.line);
    try std.testing.expectEqual(@as(usize, 1), token.location.column);

    token = lexer.next();
    try std.testing.expectEqual(TokenType.identifier, token.token_type);
    try std.testing.expectEqualStrings("span", token.text);
    try std.testing.expectEqual(@as(usize, 2), token.location.line);
    try std.testing.expectEqual(@as(usize, 1), token.location.column);
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
