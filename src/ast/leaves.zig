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
    // directive,
    heading,
    paragraph,
    // reference,
};

/// The type-specific content of a Leaf block
pub const LeafData = union(LeafType) {
    alert: Alert,
    linebreak: void,
    code: Code,
    // directive: Directive,
    heading: Heading,
    paragraph: void,
    // reference: Reference,

    pub fn deinit(self: *LeafData, gpa: Allocator) void {
        switch (self.*) {
            .heading => |*h| h.deinit(gpa),
            .code => |*c| c.deinit(gpa),
            // .directive => |*d| d.deinit(gpa),
            .alert => |*a| a.deinit(gpa),
            inline else => {},
        }
    }

    pub fn print(self: LeafData, depth: u8) void {
        switch (self) {
            .heading => |h| h.print(depth),
            .code => |c| c.print(depth),
            // .directive => |d| d.print(depth),
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

/// Raw code or other preformatted content
/// TODO: Split into "Code" and "Directive" to have explicit "Directive" types
pub const Code = struct {
    // The opening tag, e.g. "```", that has to be matched to end the block
    opener: ?[]const u8 = null,
    tag: ?[]const u8 = null,
    directive: ?[]const u8 = null,
    text: ?[]const u8 = "",

    pub fn deinit(c: *Code, gpa: Allocator) void {
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

/// Directive or Admonition box
/// This is still TODO. Similar to the Alert, but using the fenced-block syntax.
pub const Directive = struct {
    // The opening tag, e.g. "```", that has to be matched to end the block
    opener: ?[]const u8 = null,
    directive: ?[]const u8 = null,

    pub fn deinit(c: *Directive, gpa: Allocator) void {
        if (c.directive) |directive| gpa.free(directive);
        if (c.text) |text| gpa.free(text);
    }

    pub fn print(c: Directive, depth: u8) void {
        debug.printIndent(depth);
        var directive: []const u8 = "";
        if (c.directive) |d| directive = d;
        debug.print("directive: '{s}'\n", .{directive});
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
