# Agent Rules for Zempl

This document contains coding conventions and rules that agents must follow when working on the Zempl project.

## Zig Naming Conventions

When writing Zig code, follow these naming conventions from the Zig Language Reference:

### General Rules

- `camelCaseFunctionName` - Functions (that don't return types)
- `TitleCaseTypeName` - Types and type aliases
- `snake_case_variable_name` - Variables
- `snake_case` - Namespaces (structs with 0 fields, never instantiated)

### Detailed Rules

1. **Namespaces**: If `x` is a `struct` with 0 fields and is never meant to be instantiated, `x` is a "namespace" and should be `snake_case`.

2. **Types**: If `x` is a `type` or `type` alias, `x` should be `TitleCase`.

3. **Functions returning types**: If `x` is callable and `x`'s return type is `type`, then `x` should be `TitleCase`.

4. **Other callable**: If `x` is otherwise callable (functions), then `x` should be `camelCase`.

5. **Everything else**: Otherwise, `x` should be `snake_case`.

6. **Acronyms**: Even 2-letter acronyms follow these conventions (e.g., use `Html` not `HTML`, `Url` not `URL`).

### File Naming

File names fall into two categories:

1. **Types**: If the file (implicitly a struct) has top-level fields, use `TitleCase.zig`
2. **Namespaces**: If the file has no fields (just functions/types), use `snake_case.zig`

Directory names should be `snake_case`.

### Examples

```zig
const namespace_name = @import("dir_name/file_name.zig");
const TypeName = @import("dir_name/TypeName.zig");
var global_var: i32 = undefined;
const const_name = 42;
const PrimitiveTypeAlias = f32;

const StructName = struct {
    field: i32,
};
const StructAlias = StructName;

fn camelCaseFunction() void {}
```

## Zempl-Specific Conventions

### File Organization

- Files with top-level fields (the file itself is a struct with fields) should be `TitleCase.zig`
- Files without top-level fields (exporting types or functions) should be `snake_case.zig`
- Example: `zig_parse.zig` - has no top-level fields, exports functions
- Example: `lexer.zig` - has no top-level fields, exports `Lexer` type
- Example: `zig/Parse.zig` - has top-level fields (gpa, source, tokens, etc.), is a type itself

### Testing

- Tests are co-located with implementation using `test` blocks
- Use `std.testing.refAllDecls(@This())` in main.zig to discover all tests
- Run tests with `zig build test`

## General Guidelines

- When in doubt, follow the Zig standard library conventions
- If an established convention exists (like `ENOENT`), follow it
- Do what makes sense for readability and clarity