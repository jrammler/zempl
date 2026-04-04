## Why

Currently, attribute values in zempl templates are either static strings (`class="card"`) or full Zig expressions (`href={url}`). This makes string interpolation awkward—callers must pre-assemble interpolated strings in code blocks before passing them to templates. Native interpolation syntax like `href="/items/{id}"` would let template authors mix literals and expressions naturally, matching how HTML authors think about attribute values.

## What Changes

- Attribute values are always quoted strings with optional `{expression}` interpolation
- The old bare `{expression}` syntax for attributes is removed
- The AST stores attribute values as ordered segments (literals + expressions)
- Codegen emits sequential write calls for each segment
- The `escapeAttribute` runtime function is replaced with segment-aware rendering
- Documentation updated to reflect the new attribute syntax

## Capabilities

### New Capabilities
- `attribute-interpolation`: Attribute values support `{expression}` interpolation within quoted strings, e.g. `href="/items/{id}"`
- `segment-based-attribute-value`: The AST represents attribute values as an ordered list of literal and expression segments

### Modified Capabilities
- `attribute-parsing`: Removes bare `{expression}` syntax; all dynamic values must use interpolation within quoted strings

## Impact

- `src/zempl/ast.zig`: `HtmlAttribute.value` changes from `[]const u8` to a segment list type
- `src/zempl/parser.zig`: Attribute value parsing rewritten to scan for interpolation within quoted strings
- `src/zempl/codegen.zig`: Attribute code generation rewritten to emit per-segment writes
- `src/zempl/lexer.zig`: May need new token or modified string scanning for interpolation
- `test/`: Parser and codegen tests updated for new syntax
- `test/templates/*.zempl`: Example templates updated to new syntax
- `README.md`: Updated attribute syntax documentation and examples
