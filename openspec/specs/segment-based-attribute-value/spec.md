# Segment-Based Attribute Value

## Purpose

Define the segment-based representation of attribute values in the Zempl AST and code generation.

## Requirements

### Requirement: Attribute Value Segment Type

The AST SHALL represent attribute values as an ordered list of segments, each tagged as either a string literal or a Zig expression.

#### Scenario: Segment type definition

- **WHEN** the AST module is imported
- **THEN** an `AttributeValueSegment` tagged union exists with variants `.literal` (carrying `[]const u8`) and `.expression` (carrying `[]const u8`)

### Requirement: HtmlAttribute Uses Segment List

The `HtmlAttribute` struct SHALL use a segment list instead of a single `[]const u8` value field.

#### Scenario: Attribute with segments

- **WHEN** a parser produces an `HtmlAttribute`
- **THEN** the `value` field is a slice of `AttributeValueSegment`
- **AND** each segment is either a `.literal` or `.expression`

### Requirement: Codegen Emits Per-Segment Writes

Code generation SHALL emit one write call per segment, wrapping the entire sequence in attribute quotes.

#### Scenario: Mixed segments

- **WHEN** codegen processes an attribute with segments `[literal("/items/"), expression("id")]`
- **THEN** the generated code writes ` href="`, then `/items/`, then the value of `id`, then `"`
- **AND** literal segments are written as string literals
- **AND** expression segments are written as raw Zig expressions

#### Scenario: Single literal segment

- **WHEN** codegen processes an attribute with one literal segment `"card"`
- **THEN** the generated code is equivalent to the current `escapeAttribute(writer, "class", "card")` output

#### Scenario: Single expression segment

- **WHEN** codegen processes an attribute with one expression segment `url`
- **THEN** the generated code writes ` href="`, then the value of `url`, then `"`

### Requirement: HTML Escaping for Literal Segments

Literal segments in attribute values SHALL have HTML attribute escaping applied.

#### Scenario: Literal with special characters

- **WHEN** a literal segment contains `"` or `&`
- **THEN** the generated code escapes those characters for the HTML attribute context
