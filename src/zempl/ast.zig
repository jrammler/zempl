const std = @import("std");

/// HTML element node
pub const HtmlElement = struct {
    tag_name: []const u8,
    attributes: []HtmlAttribute,
    children: []HtmlNode,
    is_void: bool,

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

/// A segment within an attribute value — either a literal string or a Zig expression
pub const AttributeValueSegment = union(enum) {
    literal: []const u8,
    expression: []const u8,

    pub fn deinit(self: AttributeValueSegment, allocator: std.mem.Allocator) void {
        switch (self) {
            .literal => |text| allocator.free(text),
            .expression => |expr| allocator.free(expr),
        }
    }
};

/// HTML attribute (name=value)
pub const HtmlAttribute = struct {
    name: []const u8,
    value: []AttributeValueSegment,

    pub fn deinit(self: HtmlAttribute, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.value) |segment| {
            segment.deinit(allocator);
        }
        allocator.free(self.value);
    }
};

/// HTML text content node
pub const HtmlText = struct {
    content: []const u8,

    pub fn deinit(self: HtmlText, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
    }
};

/// HTML comment node (<!-- -->)
pub const HtmlDeclaration = struct {
    content: []const u8,

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
    is_public: bool,
    params: []const u8,
    body: []HtmlNode,

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
    expr: []const u8,

    pub fn deinit(self: ZemplExpression, allocator: std.mem.Allocator) void {
        allocator.free(self.expr);
    }
};

/// Code block @{statements}
pub const ZemplCodeBlock = struct {
    statements: []const u8,

    pub fn deinit(self: ZemplCodeBlock, allocator: std.mem.Allocator) void {
        allocator.free(self.statements);
    }
};

/// Component call @Component(args) or @Namespace.Component(args)
pub const ZemplComponentCall = struct {
    component_name: [][]const u8,
    args: []ZemplArg,

    pub fn deinit(self: ZemplComponentCall, allocator: std.mem.Allocator) void {
        for (self.component_name) |segment| {
            allocator.free(segment);
        }
        allocator.free(self.component_name);
        for (self.args) |arg| {
            arg.deinit(allocator);
        }
        allocator.free(self.args);
    }
};

/// Argument in a component call
pub const ZemplArg = struct {
    expr: []const u8,

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
    condition: []const u8,
    then_body: []HtmlNode,
    else_body: ?[]HtmlNode,

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
    captures: [][]const u8,
    iterables: [][]const u8,
    body: []HtmlNode,

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
pub const ZemplWhile = struct {
    condition: []const u8,
    body: []HtmlNode,

    pub fn deinit(self: *ZemplWhile, allocator: std.mem.Allocator) void {
        allocator.free(self.condition);
        for (self.body) |*node| {
            node.deinit(allocator);
        }
        allocator.free(self.body);
    }
};

/// Zempl import: const NAME = zimport("path.zempl");
pub const ZemplImport = struct {
    const_name: []const u8,
    path: []const u8,
    is_public: bool,
    member_path: [][]const u8,

    pub fn deinit(self: ZemplImport, allocator: std.mem.Allocator) void {
        allocator.free(self.const_name);
        allocator.free(self.path);
        for (self.member_path) |segment| {
            allocator.free(segment);
        }
        allocator.free(self.member_path);
    }
};

/// Top-level item in a zempl file (either a Zig declaration or a zempl component)
pub const ZemplItem = union(enum) {
    declaration: []const u8, // Source text of Zig const/var/fn declaration
    component: ZemplComponent,
    import: ZemplImport,

    pub fn deinit(self: ZemplItem, allocator: std.mem.Allocator) void {
        switch (self) {
            .declaration => |decl| allocator.free(decl),
            .component => |comp| comp.deinit(allocator),
            .import => |imp| imp.deinit(allocator),
        }
    }
};

/// Complete zempl file AST
pub const ZemplFile = struct {
    items: []ZemplItem,

    pub fn deinit(self: ZemplFile, allocator: std.mem.Allocator) void {
        for (self.items) |item| {
            item.deinit(allocator);
        }
        allocator.free(self.items);
    }
};
