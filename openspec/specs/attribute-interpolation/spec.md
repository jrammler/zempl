# Attribute Interpolation

## Purpose

Define how attribute values with string interpolation are parsed and represented in the Zempl template language.

## Requirements

### Requirement: Attribute String Literal

The parser SHALL accept a plain quoted string as an attribute value with no interpolation.

#### Scenario: Plain static string

- **WHEN** the template contains `class="card"`
- **THEN** the attribute value is a single literal segment with content `card`
- **AND** no expression segments are present

#### Scenario: Empty string

- **WHEN** the template contains `title=""`
- **THEN** the attribute value is a single literal segment with empty content

### Requirement: Attribute Single Interpolation

The parser SHALL accept a quoted string containing a single `{expression}` interpolation.

#### Scenario: Expression at end

- **WHEN** the template contains `href="/items/{id}"`
- **THEN** the attribute value has two segments: literal `/items/` followed by expression `id`

#### Scenario: Expression at start

- **WHEN** the template contains `data-prefix="{prefix}-value"`
- **THEN** the attribute value has two segments: expression `prefix` followed by literal `-value`

#### Scenario: Expression only

- **WHEN** the template contains `href="{url}"`
- **THEN** the attribute value has one segment: expression `url`

### Requirement: Attribute Multiple Interpolations

The parser SHALL accept a quoted string containing multiple `{expression}` interpolations.

#### Scenario: Two expressions with literal between

- **WHEN** the template contains `href="/users/{userId}/items/{itemId}"`
- **THEN** the attribute value has five segments: literal `/users/`, expression `userId`, literal `/items/`, expression `itemId`, and trailing literal (empty if string ends)

### Requirement: Complex Expressions in Interpolation

Interpolation SHALL support any valid Zig expression, not just identifiers.

#### Scenario: Property access

- **WHEN** the template contains `href="/items/{item.id}"`
- **THEN** the expression segment contains `item.id`

#### Scenario: Function call

- **WHEN** the template contains `href="/api/{encodePath(name)}"`
- **THEN** the expression segment contains `encodePath(name)`

#### Scenario: Binary expression

- **WHEN** the template contains `title="{count + 1} items"`
- **THEN** the expression segment contains `count + 1`

### Requirement: Removed Bare Expression Syntax

The old bare `{expression}` syntax (without surrounding quotes) SHALL be rejected for attribute values.

#### Scenario: Bare expression rejected

- **WHEN** the template contains `href={url}`
- **THEN** the parser produces a parse error

### Requirement: Boolean Attributes

Boolean attributes (e.g. `disabled` with no `=`) SHALL continue to work unchanged. Dynamic boolean attributes (e.g. `disabled="{isDisabled}"`) SHALL render the attribute only when the expression is truthy.

#### Scenario: Static boolean attribute

- **WHEN** the template contains `<input disabled>`
- **THEN** the attribute value is an empty segment list
- **AND** codegen emits `try writer.writeAll(" disabled")`

#### Scenario: Dynamic boolean attribute

- **WHEN** the template contains `<input disabled="{isDisabled}">`
- **THEN** the attribute value is a single expression segment with content `isDisabled`
- **AND** codegen emits `writeAttribute(writer, "disabled", isDisabled)` which renders the attribute when truthy, omits it when falsy
