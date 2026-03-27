# Zempl

Zempl is an HTML template engine for Zig. It transforms `.zempl` files into `.zig` source code at compile time, producing functions that write directly to a `std.Io.Writer` without any memory allocation.

## Usage

### Add dependency using zig fetch

```bash
zig fetch --save "git+https://github.com/jrammler/zempl#main"
```

### Build templates in build.zig

In your `build.zig`, add the zempl templates as a module:

```zig
const std = @import("std");
const zempl = @import("zempl");

pub fn build(b: *std.Build) void {
    ...
    const templates = try zempl.buildTemplateModule(b, b.path("path/to/templates.zempl"));
    exe.root_module.addImport("templates", templates);
    ...
}
```

The templates are compiled into a module you can import in your Zig code.

Each public component becomes a function `fn(writer: *std.Io.Writer, params...) !void`.

### Calling Templates

Import the templates module and call components like regular functions:

```zig
const std = @import("std");
const templates = @import("templates");

pub fn main() !void {
    var buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var file_writer = stdout.writer(&buf);
    const writer = &file_writer.interface;

    try templates.Page(writer, "Hello");

    try writer.flush();
}
```

## Syntax

### Components

Define reusable components with the `zempl` keyword:

```zig
zempl Heading(title: []const u8) {
    <h1 class="heading">{title}</h1>
}

pub zempl Card(title: []const u8, showHeader: bool) {
    <div class="card">
        @if (showHeader) {
            <div class="card-header">
                @Heading(title)
            </div>
        } @else {
            <div class="card-header">
                <p>No header</p>
            </div>
        }
        <div class="card-body">
            <p>Welcome!</p>
        </div>
    </div>
}
```

Components are public if declared with `pub zempl`, private otherwise.

### Expressions

Interpolate values with curly braces:

```zig
<p>Hello, {name}!</p>
<div>Count: {count}</div>
```

### Code Blocks

Execute Zig code with `@{...}`:

```zig
@{
    var n = count;
}
@while (n > 0) {
    <span>{n}</span>
    @{ n -= 1; }
}
```

### Control Flow

#### @if / @else

```zig
@if (showHeader) {
    <div class="header">Title</div>
} @else {
    <div class="no-header"></div>
}
```

#### @for

```zig
@for (items) |item| {
    <li>{item}</li>
}
```

#### @while

```zig
@while (count > 0) {
    <span>{count}</span>
    @{ count -= 1; }
}
```

### Component Calls

Call components with `@ComponentName(args)`:

```zig
@Card("Welcome", true)
@Heading("Hello")
@list.List(&.{ "apple", "banana", "cherry" })
```

Use `@Namespace.ComponentName(args)` for namespaced components.

### Imports

Import templates using `zimport`:

```zig
const Card = zimport("components/card.zempl").Card;
const list = zimport("components/list.zempl");
const templates = zimport("path/to/templates.zempl");
```

Top-level public components from imported files become accessible via the returned struct.

### Zig Declarations

Include arbitrary Zig code outside of zempl components:

```zig
const std = @import("std");

const Card = zimport("components/card.zempl").Card;

pub zempl Page(title: []const u8) {
    <html>
        <head><title>{title}</title></head>
        <body>
            @Card(title, true)
        </body>
    </html>
}
```

Zig declarations are copied directly into the output and can appear anywhere in the file.

### HTML Elements

Standard HTML elements are written as-is:

```zig
<div class="container">
    <h1>Welcome</h1>
    <p>This is a paragraph.</p>
    <img src="image.png" />
</div>
```

Void elements (like `img`, `br`, `hr`, `input`) are self-closing.

### HTML Escaping

Zempl automatically escapes the following characters in expressions and dynamic attribute values:

- `<` becomes `&lt;`
- `>` becomes `&gt;`
- `&` becomes `&amp;`
- `"` becomes `&quot;`
- `'` becomes `&#39;`

**Expression interpolation `{expr}`** values are HTML-escaped.

**Dynamic attribute values** are HTML-escaped.

**Static text content** is not HTML-escaped (written as-is).

### Attributes

HTML attributes with static values:

```zig
<div class="card" id="main">
    <a href="https://example.com">Link</a>
</div>
```

Dynamic attributes use `{value}` syntax:

```zig
<a href={url}>Click here</a>
```

Escape `@` in text with `@@`:

```zig
<span>Email: <a href="mailto:info@example.com">info@@example.com</a></span>
```

## Runtime

Zempl includes a runtime library (`runtime/runtime.zig`) that templates import automatically. This provides the base functionality for rendering HTML.

## Example

See `test/templates/` for a complete example with components, imports, and control flow.
