const std = @import("std");
const Location = @import("error.zig").Location;

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
    value: []const u8, // Source text of Zig expression
    location: Location,
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
    params: []const u8, // Source text of parameter list (e.g., "(title: []const u8)")
    body: []HtmlNode, // Body is HTML content
    location: Location,
};

/// Expression interpolation {expr}
pub const ZemplExpression = struct {
    expr: []const u8, // Source text of Zig expression
    location: Location,
};

/// Code block @{statements}
pub const ZemplCodeBlock = struct {
    statements: []const u8, // Source text of Zig statements
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
    expr: []const u8, // Source text of Zig expression for the argument
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
    condition: []const u8, // Source text of Zig expression for condition
    then_body: []HtmlNode,
    else_body: ?[]HtmlNode, // Optional else branch
    location: Location,
};

/// @for (item in iterable) { body }
pub const ZemplFor = struct {
    iterator_var: []const u8, // Variable name like "item"
    iterable: []const u8, // Source text of Zig expression for iterable
    body: []HtmlNode,
    location: Location,
};

/// @while (condition) { body }
/// @while (condition) { body } or @while (condition) |capture| { body }
pub const ZemplWhile = struct {
    condition: []const u8, // Source text of Zig expression for condition
    capture: ?[]const u8, // Optional capture variable name (e.g., "item" in |item|)
    body: []HtmlNode,
    location: Location,
};

/// Top-level item in a zempl file (either a Zig declaration or a zempl component)
pub const ZemplItem = union(enum) {
    declaration: []const u8, // Source text of Zig const/var/fn declaration
    component: ZemplComponent,
};

/// Complete zempl file AST
pub const ZemplFile = struct {
    items: []ZemplItem,
    location: Location,
};
