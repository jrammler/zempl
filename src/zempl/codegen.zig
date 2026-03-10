const std = @import("std");
const ZemplFile = @import("ast.zig").ZemplFile;
const ZemplItem = @import("ast.zig").ZemplItem;
const ZemplComponent = @import("ast.zig").ZemplComponent;
const HtmlNode = @import("ast.zig").HtmlNode;
const HtmlElement = @import("ast.zig").HtmlElement;
const ZemplControlFlow = @import("ast.zig").ZemplControlFlow;
const ZemplIf = @import("ast.zig").ZemplIf;
const ZemplFor = @import("ast.zig").ZemplFor;
const ZemplWhile = @import("ast.zig").ZemplWhile;
const ZemplComponentCall = @import("ast.zig").ZemplComponentCall;
const ZemplExpression = @import("ast.zig").ZemplExpression;
const ZemplCodeBlock = @import("ast.zig").ZemplCodeBlock;
const ZemplArg = @import("ast.zig").ZemplArg;
const HtmlAttribute = @import("ast.zig").HtmlAttribute;

const Error = error{
    WriteFailed,
};

/// Code generator that transforms zempl AST into Zig code
pub const CodeGenerator = struct {
    writer: *std.Io.Writer,

    const INDENT = "    ";

    pub fn init(writer: *std.Io.Writer) CodeGenerator {
        return .{
            .writer = writer,
        };
    }

    /// Generate Zig code from a zempl file
    pub fn generateFile(self: *CodeGenerator, file: ZemplFile) Error!void {
        for (file.items) |item| {
            try self.generateItem(item);
            try self.writer.writeAll("\n");
        }
    }

    fn generateItem(self: *CodeGenerator, item: ZemplItem) Error!void {
        switch (item) {
            .declaration => |decl| {
                // Preserve declarations as-is
                try self.writer.writeAll(decl);
                try self.writer.writeAll("\n");
            },
            .component => |comp| {
                try self.generateComponent(comp, 0);
            },
        }
    }

    fn generateComponent(self: *CodeGenerator, component: ZemplComponent, indent_level: usize) Error!void {
        // Public modifier if needed
        if (component.is_public) {
            try self.writer.writeAll("pub ");
        }

        // Function signature
        try self.writer.writeAll("fn ");
        try self.writer.writeAll(component.name);
        try self.writer.writeAll("(writer: *@import(\"std\").Io.Writer");

        // Add component parameters
        if (component.params.len > 2) { // "()" is empty
            try self.writer.writeAll(", ");
            // Remove leading "(" and trailing ")"
            const params = component.params[1 .. component.params.len - 1];
            try self.writer.writeAll(params);
        }

        try self.writer.writeAll(") !void {\n");

        // Function body
        for (component.body) |node| {
            try self.generateHtmlNode(node, indent_level + 1);
        }

        try self.writer.writeAll("}\n");
    }

    fn generateHtmlNode(self: *CodeGenerator, node: HtmlNode, indent_level: usize) Error!void {
        switch (node) {
            .element => |elem| try self.generateElement(elem, indent_level),
            .text => |text| try self.generateText(text.content, indent_level),
            .declaration => |decl| try self.generateDeclaration(decl.content, indent_level),
            .expression => |expr| try self.generateExpression(expr, indent_level),
            .code_block => |block| try self.generateCodeBlock(block, indent_level),
            .control_flow => |ctrl| try self.generateControlFlow(ctrl, indent_level),
            .component_call => |call| try self.generateComponentCall(call, indent_level),
        }
    }

    fn generateElement(self: *CodeGenerator, element: HtmlElement, indent_level: usize) Error!void {
        try self.writeIndent(indent_level);

        // Opening tag start
        try self.writer.writeAll("try writer.writeAll(\"<");
        try self.writer.writeAll(element.tag_name);
        try self.writer.writeAll("\");\n");

        // Attributes
        for (element.attributes) |attr| {
            try self.writeIndent(indent_level);
            try self.writer.writeAll("try @import(\"zempl_runtime\").escapeAttribute(writer, \"");
            try self.writer.writeAll(attr.name);
            try self.writer.writeAll("\", ");
            try self.writer.writeAll(attr.value);
            try self.writer.writeAll(");\n");
        }

        // Close opening tag
        try self.writeIndent(indent_level);
        if (element.is_void) {
            try self.writer.writeAll("try writer.writeAll(\">\");\n");
            return;
        }
        try self.writer.writeAll("try writer.writeAll(\">\");\n");

        // Children
        for (element.children) |child| {
            try self.generateHtmlNode(child, indent_level);
        }

        // Closing tag
        try self.writeIndent(indent_level);
        try self.writer.writeAll("try writer.writeAll(\"</");
        try self.writer.writeAll(element.tag_name);
        try self.writer.writeAll(">\");\n");
    }

    fn generateText(self: *CodeGenerator, content: []const u8, indent_level: usize) Error!void {
        if (content.len == 0) return;

        try self.writeIndent(indent_level);
        try self.writer.writeAll("try writer.writeAll(\"");
        try self.escapeAndWriteString(content);
        try self.writer.writeAll("\");\n");
    }

    fn generateDeclaration(self: *CodeGenerator, content: []const u8, indent_level: usize) Error!void {
        try self.writeIndent(indent_level);
        try self.writer.writeAll("try writer.writeAll(\"<!");
        try self.writer.writeAll(content);
        try self.writer.writeAll(">\");\n");
    }

    fn generateExpression(self: *CodeGenerator, expr: ZemplExpression, indent_level: usize) Error!void {
        try self.writeIndent(indent_level);
        try self.writer.writeAll("try @import(\"zempl_runtime\").escapeHtml(writer, ");
        try self.writer.writeAll(expr.expr);
        try self.writer.writeAll(");\n");
    }

    fn generateCodeBlock(self: *CodeGenerator, block: ZemplCodeBlock, indent_level: usize) Error!void {
        // Code blocks are inlined directly
        try self.writeIndent(indent_level);
        try self.writer.writeAll(block.statements);
        try self.writer.writeAll("\n");
    }

    fn generateControlFlow(self: *CodeGenerator, control: ZemplControlFlow, indent_level: usize) Error!void {
        switch (control) {
            .if_stmt => |*if_stmt| try self.generateIf(if_stmt.*, indent_level),
            .for_loop => |*for_loop| try self.generateFor(for_loop.*, indent_level),
            .while_loop => |*while_loop| try self.generateWhile(while_loop.*, indent_level),
        }
    }

    fn generateIf(self: *CodeGenerator, if_stmt: ZemplIf, indent_level: usize) Error!void {
        try self.writeIndent(indent_level);
        try self.writer.writeAll("if (");
        try self.writer.writeAll(if_stmt.condition);
        try self.writer.writeAll(") {\n");

        for (if_stmt.then_body) |node| {
            try self.generateHtmlNode(node, indent_level + 1);
        }

        try self.writeIndent(indent_level);
        try self.writer.writeAll("}");

        if (if_stmt.else_body) |else_body| {
            try self.writer.writeAll(" else {\n");

            for (else_body) |node| {
                try self.generateHtmlNode(node, indent_level + 1);
            }

            try self.writeIndent(indent_level);
            try self.writer.writeAll("}");
        }

        try self.writer.writeAll("\n");
    }

    fn generateFor(self: *CodeGenerator, for_loop: ZemplFor, indent_level: usize) Error!void {
        try self.writeIndent(indent_level);
        try self.writer.writeAll("for (");

        // Write iterables
        for (for_loop.iterables, 0..) |iterable, i| {
            if (i > 0) try self.writer.writeAll(", ");
            try self.writer.writeAll(iterable);
        }

        try self.writer.writeAll(")");

        // Write captures
        try self.writer.writeAll(" |");
        for (for_loop.captures, 0..) |capture, i| {
            if (i > 0) try self.writer.writeAll(", ");
            try self.writer.writeAll(capture);
        }
        try self.writer.writeAll("|");

        try self.writer.writeAll(" {\n");

        for (for_loop.body) |node| {
            try self.generateHtmlNode(node, indent_level + 1);
        }

        try self.writeIndent(indent_level);
        try self.writer.writeAll("}\n");
    }

    fn generateWhile(self: *CodeGenerator, while_loop: ZemplWhile, indent_level: usize) Error!void {
        try self.writeIndent(indent_level);
        try self.writer.writeAll("while (");
        try self.writer.writeAll(while_loop.condition);
        try self.writer.writeAll(") {\n");

        for (while_loop.body) |node| {
            try self.generateHtmlNode(node, indent_level + 1);
        }

        try self.writeIndent(indent_level);
        try self.writer.writeAll("}\n");
    }

    fn generateComponentCall(self: *CodeGenerator, call: ZemplComponentCall, indent_level: usize) Error!void {
        try self.writeIndent(indent_level);
        try self.writer.writeAll("try ");
        try self.writer.writeAll(call.component_name);
        try self.writer.writeAll("(writer");

        // Add arguments
        for (call.args) |arg| {
            try self.writer.writeAll(", ");
            try self.writer.writeAll(arg.expr);
        }

        try self.writer.writeAll(");\n");
    }

    fn writeIndent(self: *CodeGenerator, indent_level: usize) Error!void {
        var i: usize = 0;
        while (i < indent_level) : (i += 1) {
            try self.writer.writeAll(INDENT);
        }
    }

    fn escapeAndWriteString(self: *CodeGenerator, str: []const u8) Error!void {
        for (str) |c| {
            switch (c) {
                '\\' => try self.writer.writeAll("\\\\"),
                '"' => try self.writer.writeAll("\\\""),
                '\n' => try self.writer.writeAll("\\n"),
                '\r' => try self.writer.writeAll("\\r"),
                '\t' => try self.writer.writeAll("\\t"),
                else => try self.writer.writeByte(c),
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "codegen generates simple component" {
    const allocator = std.testing.allocator;

    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    var codegen = CodeGenerator.init(&allocating.writer);

    const component = ZemplComponent{
        .name = try allocator.dupe(u8, "Hello"),
        .is_public = false,
        .params = try allocator.dupe(u8, "()"),
        .body = try allocator.alloc(HtmlNode, 1),
        .location = undefined,
    };
    component.body[0] = .{ .text = .{ .content = try allocator.dupe(u8, "Hello World"), .location = undefined } };

    defer {
        allocator.free(component.name);
        allocator.free(component.params);
        component.body[0].text.deinit(allocator);
        allocator.free(component.body);
    }

    try codegen.generateComponent(component, 0);

    const output = allocating.written();
    try std.testing.expectEqualStrings(
        \\fn Hello(writer: *@import("std").Io.Writer) !void {
        \\    try writer.writeAll("Hello World");
        \\}
        \\
    , output);
}

test "codegen generates public component" {
    const allocator = std.testing.allocator;

    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    var codegen = CodeGenerator.init(&allocating.writer);

    const component = ZemplComponent{
        .name = try allocator.dupe(u8, "Public"),
        .is_public = true,
        .params = try allocator.dupe(u8, "()"),
        .body = &.{},
        .location = undefined,
    };

    defer {
        allocator.free(component.name);
        allocator.free(component.params);
    }

    try codegen.generateComponent(component, 0);

    const output = allocating.written();
    try std.testing.expectEqualStrings(
        \\pub fn Public(writer: *@import("std").Io.Writer) !void {
        \\}
        \\
    , output);
}

test "codegen generates component with params" {
    const allocator = std.testing.allocator;

    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    var codegen = CodeGenerator.init(&allocating.writer);

    const component = ZemplComponent{
        .name = try allocator.dupe(u8, "Greeting"),
        .is_public = false,
        .params = try allocator.dupe(u8, "(name: []const u8)"),
        .body = &.{},
        .location = undefined,
    };

    defer {
        allocator.free(component.name);
        allocator.free(component.params);
    }

    try codegen.generateComponent(component, 0);

    const output = allocating.written();
    try std.testing.expectEqualStrings(
        \\fn Greeting(writer: *@import("std").Io.Writer, name: []const u8) !void {
        \\}
        \\
    , output);
}

test "codegen generates expression interpolation" {
    const allocator = std.testing.allocator;

    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    var codegen = CodeGenerator.init(&allocating.writer);

    const expr = ZemplExpression{
        .expr = try allocator.dupe(u8, "title"),
        .location = undefined,
    };
    defer allocator.free(expr.expr);

    try codegen.generateExpression(expr, 0);

    const output = allocating.written();
    try std.testing.expectEqualStrings(
        \\try @import("zempl_runtime").escapeHtml(writer, title);
        \\
    , output);
}

test "codegen generates HTML element" {
    const allocator = std.testing.allocator;

    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    var codegen = CodeGenerator.init(&allocating.writer);

    const element = HtmlElement{
        .tag_name = try allocator.dupe(u8, "div"),
        .attributes = &.{},
        .children = &.{},
        .is_void = false,
        .location = undefined,
    };
    defer allocator.free(element.tag_name);

    try codegen.generateElement(element, 0);

    const output = allocating.written();
    try std.testing.expectEqualStrings(
        \\try writer.writeAll("<div");
        \\try writer.writeAll(">");
        \\try writer.writeAll("</div>");
        \\
    , output);
}

test "codegen generates void element" {
    const allocator = std.testing.allocator;

    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    var codegen = CodeGenerator.init(&allocating.writer);

    const element = HtmlElement{
        .tag_name = try allocator.dupe(u8, "br"),
        .attributes = &.{},
        .children = &.{},
        .is_void = true,
        .location = undefined,
    };
    defer allocator.free(element.tag_name);

    try codegen.generateElement(element, 0);

    const output = allocating.written();
    try std.testing.expectEqualStrings(
        \\try writer.writeAll("<br");
        \\try writer.writeAll(">");
        \\
    , output);
}

test "codegen generates element with attributes" {
    const allocator = std.testing.allocator;

    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    var codegen = CodeGenerator.init(&allocating.writer);

    const attributes = try allocator.alloc(HtmlAttribute, 2);
    attributes[0] = .{
        .name = try allocator.dupe(u8, "class"),
        .value = try allocator.dupe(u8, "\"container\""), // Static string value
        .location = undefined,
    };
    attributes[1] = .{
        .name = try allocator.dupe(u8, "id"),
        .value = try allocator.dupe(u8, "\"main\""), // Static string with single quotes
        .location = undefined,
    };

    const element = HtmlElement{
        .tag_name = try allocator.dupe(u8, "div"),
        .attributes = attributes,
        .children = &.{},
        .is_void = false,
        .location = undefined,
    };

    defer {
        allocator.free(element.tag_name);
        for (attributes) |attr| {
            allocator.free(attr.name);
            allocator.free(attr.value);
        }
        allocator.free(attributes);
    }

    try codegen.generateElement(element, 0);

    const output = allocating.written();
    try std.testing.expectEqualStrings(
        \\try writer.writeAll("<div");
        \\try @import("zempl_runtime").escapeAttribute(writer, "class", "container");
        \\try @import("zempl_runtime").escapeAttribute(writer, "id", "main");
        \\try writer.writeAll(">");
        \\try writer.writeAll("</div>");
        \\
    , output);
}

test "codegen generates element with dynamic attribute values" {
    const allocator = std.testing.allocator;

    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    var codegen = CodeGenerator.init(&allocating.writer);

    const attributes = try allocator.alloc(HtmlAttribute, 1);
    attributes[0] = .{
        .name = try allocator.dupe(u8, "class"),
        .value = try allocator.dupe(u8, "myClass"), // Expression value (no quotes)
        .location = undefined,
    };

    const element = HtmlElement{
        .tag_name = try allocator.dupe(u8, "div"),
        .attributes = attributes,
        .children = &.{},
        .is_void = false,
        .location = undefined,
    };

    defer {
        allocator.free(element.tag_name);
        for (attributes) |attr| {
            allocator.free(attr.name);
            allocator.free(attr.value);
        }
        allocator.free(attributes);
    }

    try codegen.generateElement(element, 0);

    const output = allocating.written();
    try std.testing.expectEqualStrings(
        \\try writer.writeAll("<div");
        \\try @import("zempl_runtime").escapeAttribute(writer, "class", myClass);
        \\try writer.writeAll(">");
        \\try writer.writeAll("</div>");
        \\
    , output);
}

test "codegen generates HTML declaration" {
    const allocator = std.testing.allocator;

    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    var codegen = CodeGenerator.init(&allocating.writer);

    const decl = @import("ast.zig").HtmlDeclaration{
        .content = try allocator.dupe(u8, "DOCTYPE html"),
        .location = undefined,
    };
    defer allocator.free(decl.content);

    try codegen.generateDeclaration(decl.content, 0);

    const output = allocating.written();
    try std.testing.expectEqualStrings(
        \\try writer.writeAll("<!DOCTYPE html>");
        \\
    , output);
}

test "codegen generates component call" {
    const allocator = std.testing.allocator;

    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    var codegen = CodeGenerator.init(&allocating.writer);

    const call = ZemplComponentCall{
        .component_name = try allocator.dupe(u8, "Header"),
        .args = &.{},
        .location = undefined,
    };
    defer allocator.free(call.component_name);

    try codegen.generateComponentCall(call, 0);

    const output = allocating.written();
    try std.testing.expectEqualStrings(
        \\try Header(writer);
        \\
    , output);
}

test "codegen generates if statement" {
    const allocator = std.testing.allocator;

    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    var codegen = CodeGenerator.init(&allocating.writer);

    var if_stmt = ZemplIf{
        .condition = try allocator.dupe(u8, "show"),
        .then_body = try allocator.alloc(HtmlNode, 1),
        .else_body = null,
        .location = undefined,
    };
    if_stmt.then_body[0] = .{ .text = .{ .content = try allocator.dupe(u8, "Yes"), .location = undefined } };

    defer {
        allocator.free(if_stmt.condition);
        if_stmt.then_body[0].text.deinit(allocator);
        allocator.free(if_stmt.then_body);
    }

    try codegen.generateIf(if_stmt, 0);

    const output = allocating.written();
    try std.testing.expectEqualStrings(
        \\if (show) {
        \\    try writer.writeAll("Yes");
        \\}
        \\
    , output);
}

test "codegen generates for loop" {
    const allocator = std.testing.allocator;

    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    var codegen = CodeGenerator.init(&allocating.writer);

    var for_loop = ZemplFor{
        .iterables = try allocator.dupe([]const u8, &.{try allocator.dupe(u8, "items")}),
        .captures = try allocator.dupe([]const u8, &.{try allocator.dupe(u8, "item")}),
        .body = try allocator.alloc(HtmlNode, 1),
        .location = undefined,
    };
    for_loop.body[0] = .{ .text = .{ .content = try allocator.dupe(u8, "."), .location = undefined } };

    defer {
        for (for_loop.iterables) |it| allocator.free(it);
        allocator.free(for_loop.iterables);
        for (for_loop.captures) |cap| allocator.free(cap);
        allocator.free(for_loop.captures);
        for_loop.body[0].text.deinit(allocator);
        allocator.free(for_loop.body);
    }

    try codegen.generateFor(for_loop, 0);

    const output = allocating.written();
    try std.testing.expectEqualStrings(
        \\for (items) |item| {
        \\    try writer.writeAll(".");
        \\}
        \\
    , output);
}

test "codegen generates while loop" {
    const allocator = std.testing.allocator;

    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    var codegen = CodeGenerator.init(&allocating.writer);

    var while_loop = ZemplWhile{
        .condition = try allocator.dupe(u8, "running"),
        .body = try allocator.alloc(HtmlNode, 1),
        .location = undefined,
    };
    while_loop.body[0] = .{ .text = .{ .content = try allocator.dupe(u8, "."), .location = undefined } };

    defer {
        allocator.free(while_loop.condition);
        while_loop.body[0].text.deinit(allocator);
        allocator.free(while_loop.body);
    }

    try codegen.generateWhile(while_loop, 0);

    const output = allocating.written();
    try std.testing.expectEqualStrings(
        \\while (running) {
        \\    try writer.writeAll(".");
        \\}
        \\
    , output);
}
