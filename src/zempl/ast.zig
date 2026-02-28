const std = @import("std");
const Location = @import("error.zig").Location;

/// HTML element node
pub const HtmlElement = struct {
    tag_name: []const u8,
    attributes: []HtmlAttribute,
    children: []HtmlNode,
    is_void: bool,
    location: Location,

    pub fn deinit(self: HtmlElement, allocator: std.mem.Allocator) void {
        allocator.free(self.tag_name);
        for (self.attributes) |attr| {
            attr.deinit(allocator);
        }
        allocator.free(self.attributes);
        for (self.children) |*child| {
            child.deinit(allocator);
        }
        allocator.free(self.children);
    }
};

/// HTML attribute (name=value)
pub const HtmlAttribute = struct {
    name: []const u8,
    value: []const u8, // Source text of Zig expression
    location: Location,

    pub fn deinit(self: HtmlAttribute, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value);
    }
};

/// HTML text content node
pub const HtmlText = struct {
    content: []const u8,
    location: Location,

    pub fn deinit(self: HtmlText, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
    }
};

/// HTML comment node (<!-- -->)
pub const HtmlDeclaration = struct {
    content: []const u8,
    location: Location,

    pub fn deinit(self: HtmlDeclaration, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
    }
};

/// HTML node types (elements, text, comments, doctype)
pub const HtmlNode = union(enum) {
    element: HtmlElement,
    text: HtmlText,
    declaration: HtmlDeclaration,
    expression: ZemplExpression, // {expr} inside HTML
    code_block: ZemplCodeBlock, // @{...} inside HTML
    control_flow: ZemplControlFlow, // @if, @for, @while inside HTML
    component_call: ZemplComponentCall, // @Component() inside HTML

    pub fn deinit(self: *HtmlNode, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .element => |elem| elem.deinit(allocator),
            .text => |text| text.deinit(allocator),
            .declaration => |decl| decl.deinit(allocator),
            .expression => |expr| expr.deinit(allocator),
            .code_block => |block| block.deinit(allocator),
            .control_flow => |*ctrl| ctrl.deinit(allocator),
            .component_call => |call| call.deinit(allocator),
        }
    }
};

/// Zempl component definition
pub const ZemplComponent = struct {
    name: []const u8,
    is_public: bool, // pub zempl vs zempl
    params: []const u8, // Source text of parameter list (e.g., "(title: []const u8)")
    body: []HtmlNode, // Body is HTML content
    location: Location,

    pub fn deinit(self: ZemplComponent, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.params);
        for (self.body) |*node| {
            node.deinit(allocator);
        }
        allocator.free(self.body);
    }
};

/// Expression interpolation {expr}
pub const ZemplExpression = struct {
    expr: []const u8, // Source text of Zig expression
    location: Location,

    pub fn deinit(self: ZemplExpression, allocator: std.mem.Allocator) void {
        allocator.free(self.expr);
    }
};

/// Code block @{statements}
pub const ZemplCodeBlock = struct {
    statements: []const u8, // Source text of Zig statements
    location: Location,

    pub fn deinit(self: ZemplCodeBlock, allocator: std.mem.Allocator) void {
        allocator.free(self.statements);
    }
};

/// Component call @Component(args)
pub const ZemplComponentCall = struct {
    component_name: []const u8,
    args: []ZemplArg, // Arguments to the component
    location: Location,

    pub fn deinit(self: ZemplComponentCall, allocator: std.mem.Allocator) void {
        allocator.free(self.component_name);
        for (self.args) |arg| {
            arg.deinit(allocator);
        }
        allocator.free(self.args);
    }
};

/// Argument in a component call
pub const ZemplArg = struct {
    expr: []const u8, // Source text of Zig expression for the argument
    location: Location,

    pub fn deinit(self: ZemplArg, allocator: std.mem.Allocator) void {
        allocator.free(self.expr);
    }
};

/// Control flow constructs
pub const ZemplControlFlow = union(enum) {
    if_stmt: ZemplIf,
    for_loop: ZemplFor,
    while_loop: ZemplWhile,

    pub fn deinit(self: *ZemplControlFlow, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .if_stmt => |*if_stmt| if_stmt.deinit(allocator),
            .for_loop => |*for_loop| for_loop.deinit(allocator),
            .while_loop => |*while_loop| while_loop.deinit(allocator),
        }
    }
};

/// @if (condition) { then_body } @else { else_body }
pub const ZemplIf = struct {
    condition: []const u8, // Source text of Zig expression for condition
    then_body: []HtmlNode,
    else_body: ?[]HtmlNode, // Optional else branch
    location: Location,

    pub fn deinit(self: *ZemplIf, allocator: std.mem.Allocator) void {
        allocator.free(self.condition);
        for (self.then_body) |*node| {
            node.deinit(allocator);
        }
        allocator.free(self.then_body);
        if (self.else_body) |else_body| {
            for (else_body) |*node| {
                node.deinit(allocator);
            }
            allocator.free(else_body);
        }
    }
};

/// @for (item in iterable) { body }
pub const ZemplFor = struct {
    captures: [][]const u8, // Variable name like "item"
    iterables: [][]const u8, // Source text of Zig expression for iterable
    body: []HtmlNode,
    location: Location,

    pub fn deinit(self: *ZemplFor, allocator: std.mem.Allocator) void {
        for (self.captures) |capture| {
            allocator.free(capture);
        }
        allocator.free(self.captures);
        for (self.iterables) |iterable| {
            allocator.free(iterable);
        }
        allocator.free(self.iterables);
        for (self.body) |*node| {
            node.deinit(allocator);
        }
        allocator.free(self.body);
    }
};

/// @while (condition) { body }
/// @while (condition) { body } or @while (condition) |capture| { body }
pub const ZemplWhile = struct {
    condition: []const u8, // Source text of Zig expression for condition
    body: []HtmlNode,
    location: Location,

    pub fn deinit(self: *ZemplWhile, allocator: std.mem.Allocator) void {
        allocator.free(self.condition);
        for (self.body) |*node| {
            node.deinit(allocator);
        }
        allocator.free(self.body);
    }
};

/// Top-level item in a zempl file (either a Zig declaration or a zempl component)
pub const ZemplItem = union(enum) {
    declaration: []const u8, // Source text of Zig const/var/fn declaration
    component: ZemplComponent,

    pub fn deinit(self: ZemplItem, allocator: std.mem.Allocator) void {
        switch (self) {
            .declaration => |decl| allocator.free(decl),
            .component => |comp| comp.deinit(allocator),
        }
    }
};

/// Complete zempl file AST
pub const ZemplFile = struct {
    items: []ZemplItem,
    location: Location,

    pub fn deinit(self: ZemplFile, allocator: std.mem.Allocator) void {
        for (self.items) |item| {
            item.deinit(allocator);
        }
        allocator.free(self.items);
    }
};
