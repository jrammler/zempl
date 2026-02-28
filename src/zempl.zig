// Zempl template engine library

pub const lexer = @import("zempl/lexer.zig");
pub const ast = @import("zempl/ast.zig");
pub const parser = @import("zempl/parser.zig");
pub const zig_parse = @import("zempl/zig_parse.zig");
pub const error_mod = @import("zempl/error.zig");

// Re-export main types for convenience
pub const Lexer = lexer.Lexer;
pub const Token = lexer.Token;
pub const TokenType = lexer.TokenType;
pub const ZemplFile = ast.ZemplFile;
pub const ZemplItem = ast.ZemplItem;
pub const ZemplComponent = ast.ZemplComponent;
pub const HtmlNode = ast.HtmlNode;
pub const HtmlElement = ast.HtmlElement;
pub const HtmlAttribute = ast.HtmlAttribute;
pub const Parser = parser.Parser;
pub const Location = error_mod.Location;
pub const ZemplError = error_mod.ZemplError;
pub const ErrorReporter = error_mod.ErrorReporter;

// Re-export expression parsing functions
pub const parseExpression = zig_parse.parseExpression;
pub const parseTypeExpr = zig_parse.parseTypeExpr;
