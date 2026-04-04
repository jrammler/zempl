## 1. Lexer Changes

- [x] 1.1 Change lexer to return `"` as a `.quote` token instead of scanning full `.string` content
- [x] 1.2 Update `zimport` parsing in `parser.zig` to collect tokens between quote tokens

## 2. AST Changes

- [x] 2.1 Define `AttributeValueSegment` tagged union in `ast.zig` with `.literal` and `.expression` variants
- [x] 2.2 Update `HtmlAttribute` to use `[]AttributeValueSegment` instead of `[]const u8` for value
- [x] 2.3 Add `deinit` method to properly free segment contents

## 3. Parser Changes

- [x] 3.1 Rewrite `parseAttribute()` to collect tokens between opening and closing `"` quotes
- [x] 3.2 Treat `{` inside quotes as expression start, parse with `zig_parse.parseExpression`, stop at `}`
- [x] 3.3 Remove bare `{expression}` branch from `parseAttribute()` (reject with error)

## 4. Codegen Changes

- [x] 4.1 Update `generateElement()` to iterate attribute segments instead of writing single value
- [x] 4.2 Emit `writeAll(" name=\"")` before segments, `writeAll("\"")` after
- [x] 4.3 Emit `escapeHtml` for literal and expression segments

## 8. Boolean Attribute Fix

- [x] 8.1 Represent static boolean attributes as empty segment list in parser
- [x] 8.2 Update codegen to emit bare name for empty segment lists
- [x] 8.3 Add `writeAttribute` to runtime with comptime type check
- [x] 8.4 Update codegen to use `writeAttribute` for single-expression attributes
- [x] 8.5 Add codegen test for static boolean attribute
- [x] 8.6 Add integration test for runtime-known boolean attribute
- [x] 8.7 Run `zig build test` and `zig build integration` and confirm all pass

## 5. Tests

- [x] 5.1 Add parser tests for: plain string, single interpolation, multiple interpolations
- [x] 5.2 Add parser test confirming bare `{expression}` is rejected
- [x] 5.3 Add codegen tests for: single literal, single expression, mixed segments
- [x] 5.4 Update existing parser/codegen tests that use bare `{expression}` syntax
- [x] 5.5 Update example templates in `test/templates/` to use new syntax

## 6. Documentation

- [x] 6.1 Update README.md attribute syntax section with interpolation examples

## 7. Verify

- [x] 7.1 Run `zig build test` and confirm all tests pass
- [x] 7.2 Run `zig build` and confirm compilation succeeds
