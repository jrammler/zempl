# Zempl Architecture

A templ-like template engine for Zig.

## Overview

Zempl transforms `.zempl` files into `.zig` files that can be compiled with the Zig compiler.

## Syntax

```zempl
const std = @import("std");

zempl Heading(title: []const u8) {
    <h1 class="heading">{title}</h1>
}

zempl Card(title: []const u8, showHeader: bool) {
    <div class="card">
        @if (showHeader) {
            <div class="card-header">@Heading(title)</div>
        } @else {
            <div class="card-header"><p>No header</p></div>
        }
    </div>
}

zempl Page(name: []const u8) {
    <html>
        <body>
            @Card("Welcome", true)
        </body>
    </html>
}
```

### Syntax Summary

| Feature | Syntax |
|---------|--------|
| Component definition | `zempl Name(args) { ... }` |
| Public component | `pub zempl Name(args) { ... }` (exported to other files) |
| Expression interpolation | `{expr}` |
| Code block (statements) | `@{ ... }` |
| Control flow | `@if`, `@for`, `@while` |
| Component call | `@Component(args)` |
| Attribute value | `attr=value` (no braces needed) |

### Key Design Decisions

- `@{}` does NOT create a scope - statements are inlined in function body
- Attribute values are Zig expressions (no braces needed)
- Templates can return errors implicitly
- Types are Zig types (`[]const u8`, `bool`, etc.)

### Whitespace Handling

- **Whitespace is preserved exactly** as written in the source
- All spaces, tabs, and newlines in text content are output as-is
- This allows CSS `white-space: pre` or similar to work correctly
- Empty text nodes (whitespace-only between elements) are also preserved
- **Future enhancement**: Production mode could minify HTML output

### Escaping Pitfalls

**Attribute values are Zig string literals**, not HTML strings. This affects escaping:

```zempl
// WRONG - backslash escape sequences are Zig escapes
<a href="C:\Users\name">content</a>  // \U is invalid unicode escape in Zig!

// CORRECT - use raw strings or escaped backslashes
<a href=@"C:\Users\name">content</a>  // Zig raw string
<a href="C:\\Users\\name">content</a> // Escaped backslashes
```

**Codegen escaping:** The code generator must properly escape HTML content in generated strings:
- `<` becomes `&lt;`
- `>` becomes `&gt;`
- `&` becomes `&amp;`
- `"` becomes `&quot;`
- `'` becomes `&#x27;`

User-provided strings (interpolated via `{var}`) should be HTML-escaped at runtime, not during code generation.

**No inline script/style support:** `<script>` and `<style>` tags are not supported with content to avoid complexity with `{` and `@` characters. Use external files:
```zempl
<script src="/static/app.js"></script>
```

## Architecture

```
Input (.zempl)
    │
    ▼
┌─────────────────────┐
│   Lexer             │  Custom - tokenize zempl syntax
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│   Zempl Parser      │  Custom - parse HTML and zempl constructs
│                     │  Uses Expression Parser for Zig code
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  Expression Parser  │  Forked Parse.zig from Zig stdlib
│                     │  Parses Zig expressions, declarations,
│                     │  and component signatures on demand
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│   Code Generator    │  Generate Zig code
└─────────┬───────────┘
          │
          ▼
Output (.zig)
```

## Components

### 1. Lexer
- Tokenizes zempl source based on context
- Parser drives lexer: different methods for different contexts:
  - `next()` for general tokenization (tags, identifiers, keywords, `=`)
  - `nextContent()` for HTML text content (until `<`, `{`, `@`, or `</`)
- Token types: `eof`, `identifier`, `text`
- Zempl-specific: `zempl_keyword`, `at_lbrace` (for `@{`), `lbrace`, `rbrace`
- HTML: `langle`, `rangle`, `slash`, `equal`
- Note: No string/number literals - those are part of Zig expressions handled by expression parser
- Note: No standalone `@` token - `@` is always part of an identifier
- Identifiers can start with `@` (distinguishes zempl builtins from regular identifiers)

### 2. Zempl Parser
- Parses HTML tags, attributes, text content
- Parses zempl-specific constructs: components, control flow, interpolation
- **Parser drives the lexer**: calls context-appropriate lexer methods
- Uses Expression Parser on demand for:
  - Zig expressions in `{...}` interpolation
  - Zig statements in `@{...}` code blocks
  - Conditions in `@if`, `@for`, `@while`
  - Component parameter types and signatures
  - Attribute values (which are Zig expressions)
- Handles mixed HTML and zempl content with proper nesting

### 3. Expression Parser (Forked Parse.zig)
- Forked from Zig stdlib to expose expression-level parsing functions
- `std.zig.Ast.parse()` only parses full files - we need to parse individual expressions
- Called by Zempl Parser on demand to parse Zig code within zempl templates:
  - Top-level declarations (const, var, fn)
  - Component parameter lists and types
  - Expressions in interpolation and control flow
- Provides `parseExpression()`, `parseTopLevelItem()`, etc.
- MIT license - can include in any project

### 4. Code Generator
- Generate Zig functions from zempl components
- Output HTML strings with proper escaping

## Parsing Strategy

Zempl files can contain both Zig declarations and zempl components. The parser needs to handle this mixed syntax.

### Top-Level Parsing Approach

1. **Initialize** tokenizer with full source
2. **Look at current token** to decide what to parse:
   - `const`/`var` → Parse Zig declaration (via forked Parse.zig)
   - `pub` (followed by const/var/fn) → Parse Zig declaration
   - `fn` → Parse Zig function
   - `zempl` → Hand off to zempl component parser
3. **Continue from where parser stopped**

### Required Changes to Forked Parse.zig

Add a function to parse just one top-level item and return position:

```zig
pub fn parseTopLevelItem(p: *Parse) !?Node.Index {
    // Parse const/var/fn but NOT zempl components
    // Returns the AST node and advances tok_i
}

pub fn getPosition(p: *Parse) TokenIndex {
    return p.tok_i;
}
```

### Parsing Flow

```
tokens: [const, std, =, @import, (, "std", ), ;, 
         zempl, Heading, (, title, :, [], const, u8, ), { ... }]
            │
            ▼
    parseTopLevelItem() → parses "const std = @import("std");"
            │
            ▼ (position now at "zempl")
    zempl parser handles "zempl Heading(title: []const u8) { ... }"
            │
            ▼
    continue with next token...
```

## CLI Interface

```bash
zempl <input-dir> <output-dir>
```

### Arguments

- **`<input-dir>`**: Directory to scan recursively for `.zempl` files
- **`<output-dir>`**: Directory where generated `.zig` files are placed

### Output

For each `*.zempl` file found, generates a corresponding `*.zig` file in the output directory.

Also generates `templates.zig` in the output directory:

```zig
// templates.zig - auto-generated
pub const heading = @import("heading.zig");
pub const card = @import("card.zig");
pub const page = @import("page.zig");
```

### Example Usage

```bash
# Scan ./src/templates for .zempl files
# Generate .zig files in ./zig-out/templates/
zempl ./src/templates ./zig-out/templates/
```

## Error Handling

### Error Types

| Error | Description |
|-------|-------------|
| Syntax error | Invalid zempl syntax (bad nesting, missing braces) |
| Zig parse error | Invalid Zig code in expressions or code blocks |
| HTML parse error | Malformed HTML tags or attributes |
| Type error | Type mismatch (caught by Zig compiler after generation) |

### Error Reporting

Errors must include:
- **File path**: `src/templates/page.zempl`
- **Line and column**: `Line 23, Column 5`
- **Context**: Snippet of source code around the error
- **Message**: Clear description of what went wrong

Example:
```
error: Invalid zempl syntax
  ├─ src/templates/page.zempl:23:5
  │
23 │   @if (showHeader {
   │       ^^^^^^^^^^^ expected `)` before `{`
```

## HTML Escaping

### Escaping Contexts

| Context | Characters to Escape |
|---------|---------------------|
| Text content | `& < >` |
| Attribute values | `& < > " '` |
| Inline CSS | Not supported |
| JavaScript URLs | Not supported |

### Implementation

**Static content** (HTML in templates): Escaped during code generation.

**Dynamic content** (`{var}` interpolation): Escaped at runtime by writing to a `std.Io.Writer`:

```zig
fn escapeHtml(w: *std.Io.Writer, input: []const u8) !void {
    // Write directly to writer, no allocation needed
    for (input) |c| {
        switch (c) {
            '&' => try w.writeAll("&amp;"),
            '<' => try w.writeAll("&lt;"),
            '>' => try w.writeAll("&gt;"),
            '"' => try w.writeAll("&quot;"),
            '\'' => try w.writeAll("&#x27;"),
            else => try w.writeByte(c),
        }
    }
}
```

**Alternative design**: Implement an escaping writer that wraps the underlying writer and automatically handles escaping based on context (text content vs attribute values). This allows switching escape modes dynamically.

**Note**: No support for `javascript:` URLs or inline `<style>` content to avoid XSS vulnerabilities. Use external files instead.

## HTML Parsing Details

### Void Elements

HTML void elements (self-closing, no content allowed):
`area`, `base`, `br`, `col`, `embed`, `hr`, `img`, `input`, `link`, `meta`, `param`, `source`, `track`, `wbr`

**Rules:**
- Void elements may use self-closing syntax: `<br />` or `<br>` (both accepted)
- Void elements **cannot** have content: `<br>text</br>` is an error
- Non-void elements **cannot** use self-closing: `<div />` is an error (use `<div></div>`)
- The parser maintains a list of void element names to enforce these rules

### DOCTYPE

DOCTYPE is a declaration, not an element, but parsed similarly to void elements:

```zempl
<!doctype html>
<html>
  ...
</html>
```

**Rules:**
- **Optional**: zempl components don't require DOCTYPE (they may be page fragments)
- Only full page templates would typically include DOCTYPE
- Case-insensitive: `<!DOCTYPE html>` or `<!doctype html>`
- Content is passed through to generated code without modification
- Only HTML5 doctype (`<!doctype html>`) is officially supported

### Case Sensitivity

HTML5 element names are **case-insensitive**, but zempl normalizes everything to lowercase:

```zempl
// Input can be any case
<Div Class="foo">content</Div>

// Output is always lowercase
<div class="foo">content</div>
```

**Rules:**
- Parser normalizes element names to lowercase internally
- Output is always lowercase (simpler implementation)
- Attribute names are also normalized to lowercase

### HTML Comments

HTML comments use `<!-- -->` syntax:

```zempl
<!-- This is a comment -->
<div>
  <!-- Comments can be multiline
       and contain special chars: { } @ -->
</div>
```

**Rules:**
- Comments are passed through to output unchanged
- Can contain zempl syntax characters without triggering parsing
- Useful for debugging or conditional HTML that shouldn't be processed

### Declarations (DOCTYPE and Comments)

Both DOCTYPE and HTML comments are **declarations** starting with `<!`:

- `<!doctype html>` - DOCTYPE declaration
- `<!-- comment -->` - Comment declaration

**Parsing approach:**
- Tokenizer recognizes `<!` prefix
- DOCTYPE: parsed until `>` 
- Comment: parsed until `-->`
- Both passed through to output unchanged (no zempl processing inside)
- Useful for escaping zempl syntax when needed

## File Structure

```
zempl/
├── LICENSE              # MIT
├── src/
│   ├── main.zig
│   ├── zempl/
│   │   ├── lexer.zig
│   │   ├── parser.zig         # Zempl parser (parses HTML + zempl constructs)
│   │   ├── zig/Parse.zig      # Forked from Zig stdlib
│   │   └── codegen.zig
└── test/templates/test.zempl
```
