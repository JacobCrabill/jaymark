/// leaves.zig
/// Leaf Block type implementations
const std = @import("std");

const tokens = @import("../tokens.zig");
const utils = @import("../utils.zig");
const debug = @import("../debug.zig");
const inlines = @import("inlines.zig");

const Allocator = std.mem.Allocator;

const Inline = inlines.Inline;
const InlineType = inlines.InlineType;

const Text = inlines.Text;
const Link = inlines.Link;

/// All types of Leaf blocks that can be contained in Container blocks
pub const LeafType = enum(u8) {
    alert,
    linebreak,
    code,
    directive,
    heading,
    paragraph,
    // reference,
};

/// The type-specific content of a Leaf block
pub const LeafData = union(LeafType) {
    alert: Alert,
    linebreak: void,
    code: Code,
    directive: Directive,
    heading: Heading,
    paragraph: void,
    // reference: Reference,

    pub fn deinit(self: *LeafData, gpa: Allocator) void {
        switch (self.*) {
            .heading => |*h| h.deinit(gpa),
            .code => |*c| c.deinit(gpa),
            .directive => |*d| d.deinit(gpa),
            .alert => |*a| a.deinit(gpa),
            inline else => {},
        }
    }

    pub fn print(self: LeafData, depth: u8) void {
        switch (self) {
            .heading => |h| h.print(depth),
            .code => |c| c.print(depth),
            .directive => |d| d.print(depth),
            .alert => |a| a.print(depth),
            inline else => {},
        }
    }
};

/// A heading with associated level
pub const Heading = struct {
    level: u8 = 1,
    text: []const u8 = undefined,

    pub fn deinit(h: *Heading, gpa: Allocator) void {
        gpa.free(h.text);
    }

    pub fn print(h: Heading, depth: u8) void {
        debug.printIndent(depth);
        debug.print("[H{d}] '{s}'\n", .{ h.level, h.text });
    }
};

/// Fenced block of raw code or other preformatted content, e.g.:
///
///     ```cpp
///     int x = 1;
///     ```
pub const Code = struct {
    /// The opening fence, e.g. "```", that has to be matched to end the block
    opener: ?[]const u8 = null,
    /// The info string following the opening fence, e.g. the language ("cpp")
    tag: ?[]const u8 = null,
    /// The raw (unparsed) contents of the block
    text: ?[]const u8 = "",

    pub fn deinit(c: *Code, gpa: Allocator) void {
        if (c.opener) |opener| gpa.free(opener);
        if (c.tag) |tag| gpa.free(tag);
        if (c.text) |text| gpa.free(text);
    }

    pub fn print(c: Code, depth: u8) void {
        debug.printIndent(depth);
        var tag: []const u8 = "";
        var text: []const u8 = "";
        if (c.tag) |ctag| tag = ctag;
        if (c.text) |ctext| text = ctext;
        debug.print("tag: '{s}'; body:\n{s}\n", .{ tag, text });
    }
};

/// Directive or Admonition box, using the fenced-block syntax with the
/// directive name in braces, e.g.:
///
///     ```{warning}
///     Some *formatted* text
///     ```
///
/// Unlike a Code block, the contents are parsed as inline Markdown (in the Leaf's inlines).
pub const Directive = struct {
    /// The opening fence, e.g. "```", that has to be matched to end the block
    opener: ?[]const u8 = null,
    /// The name of the directive, without the braces, e.g. "warning"
    name: ?[]const u8 = null,

    pub fn deinit(d: *Directive, gpa: Allocator) void {
        if (d.opener) |opener| gpa.free(opener);
        if (d.name) |name| gpa.free(name);
    }

    pub fn print(d: Directive, depth: u8) void {
        debug.printIndent(depth);
        debug.print("directive: '{s}'\n", .{d.name orelse ""});
    }
};

/// Github Flavored Markdown Alert
pub const Alert = struct {
    alert: ?[]const u8 = null,

    pub fn deinit(a: *Alert, gpa: Allocator) void {
        if (a.alert) |alert| gpa.free(alert);
    }

    pub fn print(a: Alert, depth: u8) void {
        debug.printIndent(depth);
        var alert: []const u8 = "";
        if (a.alert) |calert| alert = calert;
        debug.print("alert: '{s}'\n", .{alert});
    }
};

test "Directive.deinit" {
    const gpa = std.testing.allocator;
    var d = Directive{
        .opener = try gpa.dupe(u8, "```"),
        .name = try gpa.dupe(u8, "warning"),
    };
    d.deinit(gpa);
}
