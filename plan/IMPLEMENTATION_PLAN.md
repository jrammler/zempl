# Zempl Implementation Plan

This document outlines the phased implementation of Zempl, a templ-like template engine for Zig.

## Overview

Zempl transforms `.zempl` files into `.zig` files. The implementation is divided into phases, each with specific tasks and deliverables.

---

## Phase 1: Foundation & Project Setup ✓

**Goal**: Establish project structure and build infrastructure

### Task 1.1: Project Structure ✓
- Create `src/` directory structure ✓
- Set up `build.zig` with executable target ✓
- Create initial `main.zig` ✓

### Task 1.2: Error Handling Infrastructure ✓
- Define error types in `src/zempl/error.zig` ✓:
  - `SyntaxError` - Invalid zempl syntax ✓
  - `ZigParseError` - Invalid Zig code ✓
  - `HtmlParseError` - Malformed HTML ✓
  - `IoError` - File system errors ✓
- Implement error reporting with file path, line/column, and context ✓
- Implement ErrorReporter for collecting multiple errors ✓
- Add comprehensive tests ✓

### Task 1.3: Testing Infrastructure ✓
- Create `test/` directory for integration tests and fixtures ✓
- Create `test/fixtures/` for sample `.zempl` files and expected outputs ✓
- Set up `build.zig` to run `zig build test` for all tests ✓
- Remember: Unit tests go in the same file as implementation using `test` blocks ✓

**Deliverables**:
- ✓ Working build system
- ✓ Error types defined
- ✓ Test infrastructure ready
- ✓ Directory structure created

---

## Phase 2: Lexer Implementation ✓

**Goal**: Tokenize zempl source files into a stream of tokens

### Task 2.1: Token Definition ✓
- Define `Token` enum in `src/zempl/lexer.zig` ✓:
  - `eof`, `identifier`, `text` ✓
  - Zempl-specific: `zempl_keyword`, `at_lbrace` (for `@{`), `lbrace`, `rbrace` ✓
  - Identifiers can start with `@` (e.g., `@if`, `@Component`) ✓
  - HTML: `langle`, `rangle`, `slash`, `equal` ✓ (Note: `</` and `/>` are separate `<` `/` `>` tokens, not compound)
  - Note: No standalone `@` token - `@` is always part of an identifier ✓
  - Note: No `string_literal` or `number` - those are handled by expression parser ✓

### Task 2.2: Lexer Core ✓
- Implement `Lexer` struct with ✓:
  - `init(source: []const u8)` - Initialize with source ✓
  - `next() Token` - Get next token (general purpose: tags, attributes, keywords) ✓
  - `nextContent() Token` - Get token in HTML content context (returns `text` until `<`, `{`, `@`, or `</`) ✓
  - `peek() Token` - Look at next token without consuming ✓
  - `getPosition() Location` - Current position in source ✓

### Task 2.3: Context-Aware Tokenization ✓
- Parser drives lexer based on current context ✓:
  - In HTML tag context: `next()` returns tag tokens (`<`, `>`, identifiers, `=`) ✓
  - In text content context: `nextContent()` returns text chunks until special char ✓
- Lexer is stateless - parser decides what to tokenize ✓
- This avoids complex state tracking in lexer ✓
- After `=` in attribute, parser hands off to expression parser ✓

### Task 2.4: Zempl-Specific Tokens ✓
- Handle `zempl` keyword ✓
- Handle `@{` as distinct token (for code blocks) ✓
- Handle `@identifier` - identifiers can start with `@` (e.g., `@if`, `@for`, `@Component`) ✓
- Handle `{` and `}` for expression interpolation ✓

### Task 2.5: HTML Tokenization ✓
- Handle `<`, `>`, `/`, `=` as distinct tokens ✓
- Parser will recognize `</` (langle + slash) and `/>` (slash + rangle) sequences ✓
- Handle attribute names as identifiers ✓
- Handle `=` for attributes ✓
- Handle void elements as identifiers ✓
- DOCTYPE and HTML comments will be handled by parser ✓

### Task 2.6: Lexer Tests (in src/zempl/lexer.zig) ✓
- 15 test blocks covering all token types ✓
- Test for identifiers with @ ✓
- Test for HTML tokens ✓
- Test for zempl-specific tokens ✓
- Test for text content scanning ✓
- Test for peek functionality ✓
- Test for complex snippets ✓

**Deliverables**:
- ✓ Complete lexer that can tokenize all zempl syntax
- ✓ Context-aware tokenization (next() vs nextContent())
- ✓ 15 comprehensive tests all passing

---

## Phase 3: AST Definition ✓

**Goal**: Define the abstract syntax tree structure for zempl components

### Task 3.1: HTML AST Nodes ✓
- Define in `src/zempl/ast.zig` ✓:
  - `HtmlElement` - Tag name, attributes[], children[], is_void, location ✓
  - `HtmlAttribute` - Name and value (Zig expression), location ✓
  - `HtmlAttributeValue` - ZigNode (expression parser handles string literals and identifiers) ✓
  - `HtmlText` - Static text content ✓
  - `HtmlComment` - HTML comment ✓
  - `HtmlDoctype` - DOCTYPE declaration ✓
  - `HtmlNode` - Union of all HTML content types ✓

### Task 3.2: Zempl AST Nodes ✓
- Define ✓:
  - `ZemplComponent` - Name, is_public, params (ZigNode), body[], location ✓
  - `ZemplExpression` - Zig expression node, location ✓
  - `ZemplCodeBlock` - Zig statements node, location ✓
  - `ZemplComponentCall` - Component name, args[], location ✓
  - `ZemplArg` - Argument expression, location ✓
  - `ZemplControlFlow` - Union of if/for/while ✓
  - `ZemplIf`/`ZemplFor`/`ZemplWhile` - Control flow structures (while supports captures) ✓

### Task 3.3: Top-Level Structure ✓
- Define ✓:
  - `ZemplFile` - Container for declarations and components ✓
  - `ZemplItem` - Union of declaration or component ✓
  - `ZigNode` - std.zig.Ast.Node.Index for Zig AST integration ✓

### Task 3.4: AST Definition Complete ✓
- All AST types defined ✓
- Types are data containers (no behavior to test) ✓
- Will be tested implicitly by parser ✓

**Deliverables**:
- ✓ Complete AST type definitions (simplified, 133 lines)
- ✓ Integration with std.zig.Ast for Zig expressions
- ✓ While loop captures supported

---

## Phase 4: Expression Parser (Fork Parse.zig) ✓

**Goal**: Fork and adapt Zig's Parse.zig for parsing Zig expressions and declarations

### Task 4.1: Copy and Setup ✓
- Copy `lib/std/zig/Parse.zig` from Zig stdlib ✓
- Update imports (`@import("std")` instead of relative) ✓
- Remove parser_test.zig dependency ✓

### Task 4.2: Expose Required Functions ✓
- `parseTopLevelItem()` - Parse const/var/fn declarations ✓
- `parseExpression()` - Parse single expression (wraps parseExpr) ✓
- `parseTypeExpr()` - Parse type expressions ✓
- Note: These are available as functions in zig_parse.zig

### Task 4.3: Expression Parsing API ✓
- Created `zig_parse.zig` with on-demand parsing functions ✓
- Functions create Parse instances temporarily and clean up ✓
- No stored state - creates fresh tokenization for each expression ✓
- Functions: `parseExpression()`, `parseTypeExpr()`, `parseTopLevelItem()`

### Task 4.4: Tests
- ⏳ Tests for zig_parse.zig functions pending

**Deliverables**:
- ✓ Forked Parse.zig (3811 lines) with exposed functions
- ✓ zig_parse.zig with function-based API
- ⏳ Tests for expression parsing functions

**Status**: Complete - expression parsing infrastructure ready

---

## Phase 5: Zempl Parser (File Parser) 🔄

**Goal**: Parse complete zempl files, coordinating lexer, HTML parsing, and expression parser

### Task 5.1: Parser Infrastructure ✓
- Implement `Parser` struct in `src/zempl/parser.zig` ✓:
  - `init(lexer, allocator, file_path)` ✓
  - `parseFile() !ZemplFile` - basic structure ✓
  - Void elements list defined ✓
  - Memory cleanup helpers ✓

### Task 5.2: Top-Level Parsing ⏳
- Parse mixed zempl/Zig source:
  - `const`/`var` declarations → hand off to zig_parse
  - `pub const`/`pub var` declarations → hand off to zig_parse
  - `fn` declarations → hand off to zig_parse
  - `pub fn` declarations → hand off to zig_parse
  - `zempl` keyword → parse zempl component (can be `pub zempl`)
  - Track position and continue parsing after each item

### Task 5.3: HTML Content Parsing ⏳
- Parse HTML elements: `<tag>`, `</tag>`, `<tag />`
- Void elements validation
- Parse DOCTYPE and HTML comments
- Handle text content between tags

### Task 5.4: Attribute Parsing ⏳
- Parse attribute names (normalize to lowercase)
- After `=`, hand off to zig_parse to parse the value

### Task 5.5: Zempl Construct Parsing ⏳
- Component definition: `zempl Name(params) { body }`
- Expression interpolation: `{expression}`
- Code blocks: `@{statements}`
- Control flow: `@if`, `@for`, `@while`, `@else`
- Component calls: `@Component(args)`

### Task 5.6: Mixed Content Handling ⏳
- Parse HTML with embedded `{expression}` interpolation
- Parse control flow blocks containing HTML
- Handle proper nesting of HTML and zempl constructs

### Task 5.7: Parser Tests (in src/zempl/parser.zig) 🔄
- ✓ Basic initialization test
- ✓ Empty file test
- ⏳ Tests for top-level parsing
- ⏳ Tests for HTML parsing with expressions
- ⏳ Tests for zempl constructs
- ⏳ Tests for complete zempl files
- ⏳ Tests for error cases

**Deliverables**:
- ✓ Parser infrastructure
- ⏳ Complete zempl file parser
- ⏳ Can parse all zempl syntax from ARCHITECTURE.md
- ⏳ Comprehensive test suite

**Status**: Infrastructure complete, parsing logic pending

---

## Phase 6: Code Generator

**Goal**: Generate Zig code from parsed zempl AST

### Task 6.1: Codegen Infrastructure
- Implement `CodeGenerator` in `src/zempl/codegen.zig`:
  - `init(allocator: Allocator, writer: *Writer)`
  - `generate(file: ZemplFile) !void` - Generate complete file

### Task 6.2: HTML Escaping
- Implement `escapeHtml()` function:
  - Escape `&`, `<`, `>`, `"`, `'` in static content
  - Write to output writer
- Consider context-aware escaping (text vs attributes)

### Task 6.3: Component Code Generation
- Generate function signature from component definition:
  - Component name becomes function name
  - Parameters become function parameters
  - Return type: `!void` (error union)
- Generate function body:
  - Write static HTML strings
  - Insert expression interpolations with escaping
  - Insert code blocks directly

### Task 6.4: Expression Code Generation
- Generate code for `{expression}` interpolation:
  - Wrap with HTML escaping function call
  - Handle different output types

### Task 6.5: Control Flow Code Generation
- Generate `@if` as Zig `if` statement
- Generate `@for` as Zig `for` loop
- Generate `@while` as Zig `while` loop
- Handle nested control flow

### Task 6.6: Component Call Code Generation
- Generate `@Component(args)` as function call
- Pass arguments correctly
- Handle return values (void for components)

### Task 6.7: File Output Generation
- Generate imports section
- Generate all component functions
- Generate `render()` function for each component (public API)

### Task 6.8: Runtime HTML Escape Module
- Create `src/zempl/escape.zig`:
  - `HtmlEscapingWriter` - Writer wrapper that escapes HTML
  - `escapeHtml()` function for manual escaping
  - Support text and attribute contexts

### Task 6.9: Codegen Tests (in src/zempl/codegen.zig and src/zempl/escape.zig)
- Add `test` blocks for each code generation function
- Add `test` blocks for generating complete .zig files
- Add `test` blocks to verify generated code compiles
- Add `test` blocks for HTML escaping correctness

**Deliverables**:
- Working code generator
- Generated .zig files compile successfully
- HTML escaping works correctly

---

## Phase 7: File Processing & CLI

**Goal**: Implement file scanning, processing, and CLI interface

### Task 7.1: File Scanner
- Implement in `src/zempl/files.zig`:
  - `scanDirectory(path: []const u8) ![]FileEntry` - Recursively find .zempl files
  - Maintain relative paths for output structure

### Task 7.2: File Processor
- Implement `processFile(input_path, output_path) !void`:
  - Read .zempl file
  - Lex, parse, and generate
  - Write .zig output
  - Handle errors with file context

### Task 7.3: Templates.zig Generator
- Generate `templates.zig` file in output directory
- Create public imports for all generated components
- Sort components alphabetically or by dependency

### Task 7.4: CLI Implementation
- Implement in `src/main.zig`:
  - Parse command line arguments: `zempl <input-dir> <output-dir>`
  - Validate input and output directories
  - Process all files with progress reporting
  - Return appropriate exit codes

### Task 7.5: Error Reporting in CLI
- Print formatted errors with file paths and line numbers
- Show source context with error location
- Continue processing other files on error
- Summary report at end

### Task 7.6: CLI Tests (in src/main.zig and test/)
- Add `test` blocks in main.zig for argument parsing
- Add `test` blocks for file scanning
- Add `test` blocks for error handling
- Add integration tests in test/ with sample templates

**Deliverables**:
- Working CLI that processes directories
- Proper error reporting
- Generated templates.zig file

---

## Phase 8: Integration & End-to-End Testing

**Goal**: Verify complete system works together

### Task 8.1: Sample Templates
- Create `test/templates/` with sample .zempl files:
  - Simple component (Heading)
  - Component with condition (Card)
  - Component with loops (List)
  - Complete page (Page)

### Task 8.2: Integration Tests
- Test complete pipeline: .zempl → .zig → compile → render
- Verify output HTML is correct
- Test error cases produce good error messages

### Task 8.3: Performance Testing
- Test with large templates
- Measure memory usage
- Profile and optimize if needed

### Task 8.4: Edge Case Testing
- Test empty templates
- Test deeply nested structures
- Test unicode content
- Test special characters in expressions

### Task 8.5: Documentation
- Update README.md with usage instructions
- Document CLI options
- Add examples directory with working templates

**Deliverables**:
- Working end-to-end system
- Sample templates that compile and run
- Performance benchmarks
- User documentation

---

## Phase 9: Polish & Optimization

**Goal**: Improve code quality, performance, and robustness

### Task 9.1: Error Message Improvements
- Add more helpful error messages
- Suggest fixes for common errors
- Improve error context display

### Task 9.2: Performance Optimization
- Profile lexer and parser
- Optimize hot paths
- Reduce memory allocations where possible

### Task 9.3: Code Quality
- Add comprehensive inline documentation
- Ensure consistent code style
- Review and refactor as needed

### Task 9.4: Additional Features (if time permits)
- Template inheritance/extending
- Partials/includes
- Built-in filters
- Debug mode with line numbers in output
- Production mode with HTML minification (strip unnecessary whitespace)

### Task 9.5: Final Testing
- Run full test suite
- Test on different Zig versions
- Verify cross-platform compatibility

**Deliverables**:
- Polished, well-documented codebase
- Optimized performance
- Comprehensive test coverage

---

## Notes

- The plan is iterative - work through phases at your own pace
- Prioritize core functionality (lexer → parser → codegen) over polish
- Regular integration testing between phases prevents issues
- Consider parallel work on independent phases (e.g., CLI can be started early)
- Take breaks and enjoy the process - there's no rush!

---

## Testing Strategy

Zempl follows Zig's idiomatic testing pattern: **tests are co-located with implementation** using `test` blocks within the same source files. This provides better discoverability and ensures tests stay in sync with code changes.

### Testing Approach

1. **Unit Tests**: Test individual functions directly in their source files using `test` blocks
2. **Integration Tests**: Test component interactions in `test/` directory as separate `.zig` files
3. **End-to-End Tests**: Test complete workflow with sample templates in `test/` directory
4. **Error Tests**: Verify error handling and messages

### Test Organization

```
src/
├── main.zig               # Tests for CLI
├── zempl/
│   ├── lexer.zig          # Contains test blocks for lexer
│   ├── ast.zig            # Contains test blocks for AST
│   ├── zig/
│   │   └── Parse.zig      # Contains test blocks for Zig expression parser
│   ├── parser.zig         # Contains test blocks for zempl parser
│   ├── codegen.zig        # Contains test blocks for code generator
│   ├── escape.zig         # Contains test blocks for HTML escaping
│   ├── error.zig          # Contains test blocks for error types
│   └── files.zig          # Contains test blocks for file operations
test/
├── fixtures/              # Test input/output files
│   ├── simple.zempl
│   ├── heading.zempl
│   └── ...
└── integration.zig        # Integration and E2E tests
```

### Writing Tests

Example test in implementation file:

```zig
// src/zempl/lexer.zig

pub const Token = enum { ... };
pub const Lexer = struct { ... };

test "lexer handles basic tokens" {
    const source = "const std = @import(\"std\");";
    var lexer = Lexer.init(source);
    
    try std.testing.expectEqual(.keyword_const, lexer.next());
    try std.testing.expectEqual(.identifier, lexer.next());
    // ...
}

test "lexer handles zempl interpolation" {
    const source = "<h1>{title}</h1>";
    var lexer = Lexer.init(source);
    
    // Test HTML tokens and interpolation
    // ...
}
```

### Running Tests

```bash
# Run all tests (including tests in all source files)
zig build test

# Run tests in a specific file
zig test src/zempl/lexer.zig

# Run tests matching a filter
zig build test -- <filter>
```

### Integration Tests

Integration tests go in `test/integration.zig` and import the zempl modules:

```zig
// test/integration.zig

const zempl = @import("../src/zempl.zig");

test "end-to-end: simple template" {
    // Test complete pipeline
}
```

### Test Fixtures

Use `test/fixtures/` for `.zempl` files and expected `.zig` output:

```zig
test "codegen produces expected output" {
    const input = @embedFile("fixtures/simple.zempl");
    const expected = @embedFile("fixtures/simple_expected.zig");
    // Compare generated output
}
```

---

## Success Criteria

The implementation is complete when:

1. All phases have been implemented
2. All tests pass
3. Sample templates compile and render correctly
4. CLI works as specified in ARCHITECTURE.md
5. Error messages are clear and helpful
6. Code is well-documented
7. Performance is acceptable for typical use cases
