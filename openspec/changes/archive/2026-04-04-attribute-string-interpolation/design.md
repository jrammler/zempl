## Context

Currently, `HtmlAttribute` stores `value` as a single `[]const u8`. Static values include their quotes (`"card"`), dynamic values are bare expressions (`url`). Codegen writes the value verbatim into generated Zig code, relying on the presence/absence of quotes to produce valid code. This is fragile and prevents interpolation.

## Goals / Non-Goals

**Goals:**
- Support `{expr}` interpolation within quoted attribute strings
- Remove the bare `{expr}` syntax for attributes
- Store attribute values as typed segments in the AST
- Generate correct Zig code with proper HTML escaping

**Non-Goals:**
- Interpolation in text content (already supported via `{expr}` nodes)
- Escaping literal `{` or `}` inside attribute strings (users can use `&#123;` or `{"{"}`)

## Decisions

### Decision 1: Change lexer to return `"` as a token instead of `.string`

The lexer will return a `"`.quote` token instead of scanning the full string content. The parser will then collect tokens between the opening and closing `"`, treating `{` as the start of an expression — exactly like text content parsing already works.

**Rationale:** This mirrors the existing text content parsing pattern (stops at `<`, `>`, `{`, `@`). The parser already knows how to collect mixed text and expression tokens. No need for post-processing or string scanning in the parser.

### Decision 2: Store raw source text for both literals and expressions

The `AttributeValueSegment` will store:
- `.literal`: the raw text between interpolations
- `.expression`: the raw Zig expression source text (as validated by `zig_parse.parseExpression`)

**Rationale:** Codegen needs the source text to emit valid Zig code. Storing raw text avoids re-serialization and preserves the author's formatting.

### Decision 3: Codegen handles three attribute cases

**Static boolean** (`disabled`): empty segment list → emit just the name:
```zig
try writer.writeAll(" disabled");
```

**Runtime boolean** (`disabled="{isDisabled}"`): single expression segment → delegate to `writeAttribute`:
```zig
try @import("zempl_runtime").writeAttribute(writer, "disabled", isDisabled);
```

**Normal attribute** (static, interpolated, or expression-only): emit quote-wrapped segments:
```zig
try writer.writeAll(" class=\"");
try @import("zempl_runtime").escapeHtml(writer, "/items/");
try @import("zempl_runtime").escapeHtml(writer, id);
try writer.writeAll("\"");
```

**Rationale:** Boolean attributes need special handling to omit the attribute entirely when false. The runtime's `writeAttribute` uses `@typeInfo` to check the type at compile time of the generated code — if it's a bool, it renders the bare attribute or nothing; otherwise it renders `name="value"`. Empty segment list in the AST represents a static boolean (always rendered). Both literals and expressions are HTML-escaped for safety.

### Decision 4: No brace escaping

Literal `{` inside attribute strings is not supported. Users who need a literal `{` can use the HTML entity `&#123;` or wrap it in an expression: `{"{"}`.

**Rationale:** Keeps the parser simple. The escape cases are rare and have reasonable workarounds.

## Implementation Order

1. Update lexer to return `"` as a token instead of scanning full strings
2. Update `zimport` parsing to collect tokens between quotes
3. Define `AttributeValueSegment` in `ast.zig`
4. Update `HtmlAttribute` to use segment list
5. Update parser's `parseAttribute()` to collect tokens between quotes, treating `{` as expression starts
6. Update codegen to emit per-segment writes
7. Update tests and example templates
8. Update README documentation
