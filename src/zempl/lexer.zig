const std = @import("std");
const Location = @import("error.zig").Location;

/// Token types for the zempl lexer
pub const Token = enum {
    // Special tokens
    eof,

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
    langle_slash, // </
    rangle, // >
    slash_rangle, // />
    slash, // / (used in various contexts)
    equal, // =
};

/// A token with its location and optional text content
pub const TokenWithLocation = struct {
    token: Token,
    start: usize,
    end: usize,
    text: []const u8,

    pub fn init(token: Token, start: usize, end: usize, text: []const u8) TokenWithLocation {
        return .{
            .token = token,
            .start = start,
            .end = end,
            .text = text,
        };
    }
};

/// Lexer for zempl template files
pub const Lexer = struct {
    source: []const u8,
    index: usize,

    pub fn init(source: []const u8) Lexer {
        return .{
            .source = source,
            .index = 0,
        };
    }

    /// Get current position in source
    pub fn getPosition(self: Lexer) usize {
        return self.index;
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

    /// Consume current character and advance
    fn advance(self: *Lexer) ?u8 {
        if (self.index >= self.source.len) {
            return null;
        }
        const ch = self.source[self.index];
        self.index += 1;
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

    /// Check if character is valid identifier continuation (alphanumeric or underscore)
    fn isIdentifierPart(ch: u8) bool {
        return std.ascii.isAlphanumeric(ch) or ch == '_';
    }

    /// Scan an identifier
    fn scanIdentifier(self: *Lexer) TokenWithLocation {
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
            return TokenWithLocation.init(.zempl_keyword, start, self.index, text);
        }

        return TokenWithLocation.init(.identifier, start, self.index, text);
    }

    /// Scan text content until we hit a special character
    fn scanText(self: *Lexer) TokenWithLocation {
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
        return TokenWithLocation.init(.text, start, self.index, text);
    }

    /// Get next token (general purpose - for tags, attributes, etc.)
    pub fn next(self: *Lexer) TokenWithLocation {
        self.skipWhitespace();

        const start = self.index;
        const ch = self.peekChar();

        if (ch == null) {
            return TokenWithLocation.init(.eof, start, start, "");
        }

        const c = ch.?;

        // Check for HTML tokens
        if (c == '<') {
            // Check for </ (end tag)
            if (self.peekCharAhead(1) == '/') {
                _ = self.advance(); // consume '<'
                _ = self.advance(); // consume '/'
                return TokenWithLocation.init(.langle_slash, start, self.index, self.source[start..self.index]);
            }
            _ = self.advance();
            return TokenWithLocation.init(.langle, start, self.index, "<");
        }

        if (c == '>') {
            _ = self.advance();
            return TokenWithLocation.init(.rangle, start, self.index, ">");
        }

        if (c == '/') {
            // Check for /> (self-closing tag)
            if (self.peekCharAhead(1) == '>') {
                _ = self.advance(); // consume '/'
                _ = self.advance(); // consume '>'
                return TokenWithLocation.init(.slash_rangle, start, self.index, self.source[start..self.index]);
            }
            _ = self.advance();
            return TokenWithLocation.init(.slash, start, self.index, "/");
        }

        if (c == '=') {
            _ = self.advance();
            return TokenWithLocation.init(.equal, start, self.index, "=");
        }

        // Check for zempl tokens
        if (c == '{') {
            _ = self.advance();
            return TokenWithLocation.init(.lbrace, start, self.index, "{");
        }

        if (c == '}') {
            _ = self.advance();
            return TokenWithLocation.init(.rbrace, start, self.index, "}");
        }

        // Check for @{
        if (c == '@') {
            if (self.peekCharAhead(1) == '{') {
                _ = self.advance(); // consume '@'
                _ = self.advance(); // consume '{'
                return TokenWithLocation.init(.at_lbrace, start, self.index, self.source[start..self.index]);
            }
            // Otherwise it's an identifier starting with @
            return self.scanIdentifier();
        }

        // Identifier
        if (isIdentifierStart(c)) {
            return self.scanIdentifier();
        }

        // Unknown character - skip it and return next token
        _ = self.advance();
        return self.next();
    }

    /// Get next token in content context (returns text until special char)
    pub fn nextContent(self: *Lexer) TokenWithLocation {
        self.skipWhitespace();

        const start = self.index;
        const ch = self.peekChar();

        if (ch == null) {
            return TokenWithLocation.init(.eof, start, start, "");
        }

        const c = ch.?;

        // If we're at a special character, return it as a token
        if (c == '<') {
            // Check for </
            if (self.peekCharAhead(1) == '/') {
                _ = self.advance(); // consume '<'
                _ = self.advance(); // consume '/'
                return TokenWithLocation.init(.langle_slash, start, self.index, self.source[start..self.index]);
            }
            _ = self.advance();
            return TokenWithLocation.init(.langle, start, self.index, "<");
        }

        if (c == '{') {
            _ = self.advance();
            return TokenWithLocation.init(.lbrace, start, self.index, "{");
        }

        if (c == '@') {
            // Check for @{
            if (self.peekCharAhead(1) == '{') {
                _ = self.advance(); // consume '@'
                _ = self.advance(); // consume '{'
                return TokenWithLocation.init(.at_lbrace, start, self.index, self.source[start..self.index]);
            }
            // It's an @identifier
            return self.scanIdentifier();
        }

        // Otherwise scan text content
        return self.scanText();
    }

    /// Look at next token without consuming (uses next() method)
    pub fn peek(self: *Lexer) TokenWithLocation {
        const saved_index = self.index;
        const token = self.next();
        self.index = saved_index;
        return token;
    }
};

// Tests
test "Lexer initialization" {
    const source = "hello";
    var lexer = Lexer.init(source);

    try std.testing.expectEqual(@as(usize, 0), lexer.getPosition());
}

test "EOF token" {
    const source = "";
    var lexer = Lexer.init(source);

    const token = lexer.next();
    try std.testing.expectEqual(Token.eof, token.token);
}

test "Identifier token" {
    const source = "div";
    var lexer = Lexer.init(source);

    const token = lexer.next();
    try std.testing.expectEqual(Token.identifier, token.token);
    try std.testing.expectEqualStrings("div", token.text);
}

test "Zempl keyword" {
    const source = "zempl";
    var lexer = Lexer.init(source);

    const token = lexer.next();
    try std.testing.expectEqual(Token.zempl_keyword, token.token);
    try std.testing.expectEqualStrings("zempl", token.text);
}

test "Identifier with @" {
    const source = "@if";
    var lexer = Lexer.init(source);

    const token = lexer.next();
    try std.testing.expectEqual(Token.identifier, token.token);
    try std.testing.expectEqualStrings("@if", token.text);
}

test "HTML tokens" {
    const source = "< > = /";
    var lexer = Lexer.init(source);

    var token = lexer.next();
    try std.testing.expectEqual(Token.langle, token.token);

    token = lexer.next();
    try std.testing.expectEqual(Token.rangle, token.token);

    token = lexer.next();
    try std.testing.expectEqual(Token.equal, token.token);

    token = lexer.next();
    try std.testing.expectEqual(Token.slash, token.token);
}

test "End tag token" {
    const source = "</div>";
    var lexer = Lexer.init(source);

    var token = lexer.next();
    try std.testing.expectEqual(Token.langle_slash, token.token);
    try std.testing.expectEqualStrings("</", token.text);

    token = lexer.next();
    try std.testing.expectEqual(Token.identifier, token.token);
    try std.testing.expectEqualStrings("div", token.text);
}

test "Self-closing tag token" {
    const source = "/>";
    var lexer = Lexer.init(source);

    const token = lexer.next();
    try std.testing.expectEqual(Token.slash_rangle, token.token);
    try std.testing.expectEqualStrings("/>", token.text);
}

test "Zempl braces" {
    const source = "{}";
    var lexer = Lexer.init(source);

    var token = lexer.next();
    try std.testing.expectEqual(Token.lbrace, token.token);

    token = lexer.next();
    try std.testing.expectEqual(Token.rbrace, token.token);
}

test "Code block start" {
    const source = "@{";
    var lexer = Lexer.init(source);

    const token = lexer.next();
    try std.testing.expectEqual(Token.at_lbrace, token.token);
    try std.testing.expectEqualStrings("@{", token.text);
}

test "Text content" {
    const source = "Hello world";
    var lexer = Lexer.init(source);

    const token = lexer.nextContent();
    try std.testing.expectEqual(Token.text, token.token);
    try std.testing.expectEqualStrings("Hello world", token.text);
}

test "Text content stops at special char" {
    const source = "Hello <world>";
    var lexer = Lexer.init(source);

    var token = lexer.nextContent();
    try std.testing.expectEqual(Token.text, token.token);
    try std.testing.expectEqualStrings("Hello ", token.text);

    token = lexer.nextContent();
    try std.testing.expectEqual(Token.langle, token.token);
}

test "Text content with interpolation" {
    const source = "Hello {name}!";
    var lexer = Lexer.init(source);

    var token = lexer.nextContent();
    try std.testing.expectEqual(Token.text, token.token);
    try std.testing.expectEqualStrings("Hello ", token.text);

    token = lexer.nextContent();
    try std.testing.expectEqual(Token.lbrace, token.token);
}

test "Peek doesn't advance" {
    const source = "div";
    var lexer = Lexer.init(source);

    const token1 = lexer.peek();
    try std.testing.expectEqual(Token.identifier, token1.token);

    const token2 = lexer.next();
    try std.testing.expectEqual(Token.identifier, token2.token);
    try std.testing.expectEqualStrings("div", token2.text);
}

test "Complex zempl snippet" {
    const source = "<h1>{title}</h1>";
    var lexer = Lexer.init(source);

    // In tag context
    var token = lexer.next();
    try std.testing.expectEqual(Token.langle, token.token);

    token = lexer.next();
    try std.testing.expectEqual(Token.identifier, token.token);
    try std.testing.expectEqualStrings("h1", token.text);

    token = lexer.next();
    try std.testing.expectEqual(Token.rangle, token.token);

    // Switch to content context
    token = lexer.nextContent();
    try std.testing.expectEqual(Token.lbrace, token.token);

    // The expression {title} would be handled by expression parser
}
