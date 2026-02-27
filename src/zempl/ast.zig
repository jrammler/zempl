const std = @import("std");
const Location = @import("error.zig").Location;

// Forward declaration for expression parser integration
pub const ZigNode = std.zig.Ast.Node.Index;

/// HTML element node
pub const HtmlElement = struct {
    tag_name: []const u8,
    attributes: []HtmlAttribute,
    children: []HtmlNode,
    is_void: bool,
    location: Location,
};

/// HTML attribute (name=value)
pub const HtmlAttribute = struct {
    name: []const u8,
    value: HtmlAttributeValue,
    location: Location,
};

/// Value of an HTML attribute - can be static text or a Zig expression
pub const HtmlAttributeValue = union(enum) {
    static: []const u8, // Raw text value
    expression: ZigNode, // Zig expression AST node (e.g., {color})
};

/// HTML text content node
pub const HtmlText = struct {
    content: []const u8,
    location: Location,
};

/// HTML comment node (<!-- -->)
pub const HtmlComment = struct {
    content: []const u8,
    location: Location,
};

/// DOCTYPE declaration
pub const HtmlDoctype = struct {
    content: []const u8, // Usually "html" for <!DOCTYPE html>
    location: Location,
};

/// HTML node types (elements, text, comments, doctype)
pub const HtmlNode = union(enum) {
    element: HtmlElement,
    text: HtmlText,
    comment: HtmlComment,
    doctype: HtmlDoctype,
    expression: ZemplExpression, // {expr} inside HTML
    code_block: ZemplCodeBlock, // @{...} inside HTML
    control_flow: ZemplControlFlow, // @if, @for, @while inside HTML
    component_call: ZemplComponentCall, // @Component() inside HTML
};

/// Zempl component definition
pub const ZemplComponent = struct {
    name: []const u8,
    is_public: bool, // pub zempl vs zempl
    params: []ZemplParam,
    body: []HtmlNode, // Body is HTML content
    location: Location,
};

/// Component parameter (name: type)
pub const ZemplParam = struct {
    name: []const u8,
    param_type: ZigNode, // Type expression (e.g., []const u8, bool)
    location: Location,
};

/// Expression interpolation {expr}
pub const ZemplExpression = struct {
    expr: ZigNode, // Zig expression AST node
    location: Location,
};

/// Code block @{statements}
pub const ZemplCodeBlock = struct {
    statements: ZigNode, // Zig statements AST node
    location: Location,
};

/// Component call @Component(args)
pub const ZemplComponentCall = struct {
    component_name: []const u8,
    args: []ZemplArg, // Arguments to the component
    location: Location,
};

/// Argument in a component call
pub const ZemplArg = struct {
    expr: ZigNode, // Zig expression for the argument
    location: Location,
};

/// Control flow constructs
pub const ZemplControlFlow = union(enum) {
    if_stmt: ZemplIf,
    for_loop: ZemplFor,
    while_loop: ZemplWhile,
};

/// @if (condition) { then_body } @else { else_body }
pub const ZemplIf = struct {
    condition: ZigNode, // Zig expression for condition
    then_body: []HtmlNode,
    else_body: ?[]HtmlNode, // Optional else branch
    location: Location,
};

/// @for (item in iterable) { body }
pub const ZemplFor = struct {
    iterator_var: []const u8, // Variable name like "item"
    iterable: ZigNode, // Zig expression for iterable
    body: []HtmlNode,
    location: Location,
};

/// @while (condition) { body }
pub const ZemplWhile = struct {
    condition: ZigNode, // Zig expression for condition
    body: []HtmlNode,
    location: Location,
};

/// Top-level item in a zempl file (either a Zig declaration or a zempl component)
pub const ZemplItem = union(enum) {
    declaration: ZigNode, // Zig const/var/fn declaration
    component: ZemplComponent,
};

/// Complete zempl file AST
pub const ZemplFile = struct {
    items: []ZemplItem,
    location: Location,
};

// Tests
test "HtmlElement construction" {
    // Create a simple div element
    const div = HtmlElement{
        .tag_name = "div",
        .attributes = &.{},
        .children = &.{},
        .is_void = false,
        .location = .{
            .file_path = "test.zempl",
            .line = 1,
            .column = 1,
        },
    };

    try std.testing.expectEqualStrings("div", div.tag_name);
    try std.testing.expect(!div.is_void);
}

test "ZemplComponent construction" {
    const component = ZemplComponent{
        .name = "Heading",
        .is_public = false,
        .params = &.{},
        .body = &.{},
        .location = .{
            .file_path = "test.zempl",
            .line = 1,
            .column = 1,
        },
    };

    try std.testing.expectEqualStrings("Heading", component.name);
    try std.testing.expect(!component.is_public);
}

test "Public vs private component" {
    const private = ZemplComponent{
        .name = "Private",
        .is_public = false,
        .params = &.{},
        .body = &.{},
        .location = .{
            .file_path = "test.zempl",
            .line = 1,
            .column = 1,
        },
    };

    const public = ZemplComponent{
        .name = "Public",
        .is_public = true,
        .params = &.{},
        .body = &.{},
        .location = .{
            .file_path = "test.zempl",
            .line = 5,
            .column = 1,
        },
    };

    try std.testing.expect(!private.is_public);
    try std.testing.expect(public.is_public);
}

test "HtmlAttribute construction" {
    const attr = HtmlAttribute{
        .name = "class",
        .value = .{ .static = "heading" },
        .location = .{
            .file_path = "test.zempl",
            .line = 1,
            .column = 5,
        },
    };

    try std.testing.expectEqualStrings("class", attr.name);
    try std.testing.expectEqual(@as(std.meta.Tag(HtmlAttributeValue), .static), std.meta.activeTag(attr.value));
}

test "HtmlText construction" {
    const text = HtmlText{
        .content = "Hello World",
        .location = .{
            .file_path = "test.zempl",
            .line = 1,
            .column = 1,
        },
    };

    try std.testing.expectEqualStrings("Hello World", text.content);
}

test "ZemplItem union" {
    const component_item = ZemplItem{
        .component = .{
            .name = "Test",
            .is_public = false,
            .params = &.{},
            .body = &.{},
            .location = .{
                .file_path = "test.zempl",
                .line = 1,
                .column = 1,
            },
        },
    };

    try std.testing.expectEqual(@as(std.meta.Tag(ZemplItem), .component), std.meta.activeTag(component_item));
}

test "ZemplFile construction" {
    const file = ZemplFile{
        .items = &.{},
        .location = .{
            .file_path = "test.zempl",
            .line = 1,
            .column = 1,
        },
    };

    try std.testing.expectEqual(@as(usize, 0), file.items.len);
}
