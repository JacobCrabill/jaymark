const std = @import("std");
const utils = @import("../utils.zig");
const debug = @import("../debug.zig");
const tokens = @import("../tokens.zig");

const Allocator = std.mem.Allocator;

const Token = tokens.Token;

/// Styles which can be applied to Markdown text
pub const TextStyle = struct {
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    strike: bool = false,
};

/// Inlines are considered Phrasing content
/// Phrasing content represents the text in a document, and its markup
pub const InlineType = enum(u8) {
    autolink,
    codespan,
    escaped,
    image,
    linebreak,
    link,
    text,
};

pub const InlineData = union(InlineType) {
    autolink: Autolink,
    codespan: Codespan,
    escaped: u8,
    image: Image,
    linebreak: void,
    link: Link,
    text: Text,

    pub fn deinit(self: *InlineData, gpa: Allocator) void {
        switch (self.*) {
            .link => |*l| l.deinit(gpa),
            .image => |*i| i.deinit(gpa),
            .text => |*t| t.deinit(gpa),
            .codespan => |*c| c.deinit(gpa),
            .autolink => |*a| a.deinit(gpa),
            else => {},
        }
    }

    pub fn print(self: InlineData, depth: u8) void {
        switch (self) {
            .codespan, .linebreak => {
                debug.printIndent(depth);
                debug.print("Inline {s}\n", .{@tagName(self)});
            },
            .escaped => |ch| {
                debug.printIndent(depth);
                debug.print("Escaped: '\\{c}'\n", .{ch});
            },
            .link => |link| {
                debug.printIndent(depth);
                debug.print("Link:\n", .{});
                for (link.text.items) |text| {
                    text.print(depth + 1);
                }
            },
            inline else => |item| {
                item.print(depth);
            },
        }
    }
};

pub const Inline = struct {
    const Self = @This();
    open: bool = true,
    content: InlineData = undefined,

    pub fn initWithContent(content: InlineData) Inline {
        return .{ .content = content };
    }

    pub fn deinit(self: *Inline, gpa: Allocator) void {
        self.content.deinit(gpa);
        self.* = .{};
    }

    pub fn print(self: Inline, depth: u8) void {
        self.content.print(depth);
    }
};

/// Section of formatted text (single style)
/// Example: "plain text" or "**bold text**"
pub const Text = struct {
    style: TextStyle = TextStyle{},
    text: []const u8 = undefined, // The Text is assumed to own the string if 'alloc' is not null
    line: usize = 0, // Line number where this text appears
    col: usize = 0, // Column number where this text starts
    heap_text: bool = false, // Whether the text is heap-allocated

    pub fn print(self: Text, depth: u8) void {
        debug.printIndent(depth);
        debug.print("Text: '{s}' [line: {d}, col: {d}]\n", .{ self.text, self.line, self.col });
        // debug.printIndent(depth);
        // debug.print("Style: ", .{});
        // if (self.style.fg_color) |fg| {
        //     debug.print("fg: {s}", .{@tagName(fg)});
        // }
        // if (self.style.bg_color) |bg| {
        //     debug.print("bg: {s},", .{@tagName(bg)});
        // }
        // inline for (@typeInfo(TextStyle).@"struct".fields) |field| {
        //     const T: type = @TypeOf(@field(self.style, field.name));
        //     if (T == bool) {
        //         if (@field(self.style, field.name)) {
        //             debug.print("{s}", .{field.name});
        //         }
        //     }
        // }
        // debug.print("\n", .{});
    }

    pub fn deinit(self: *Text, gpa: Allocator) void {
        if (self.heap_text) {
            gpa.free(self.text);
        }
        self.* = .{};
    }
};

/// Hyperlink
pub const Link = struct {
    url: []const u8 = undefined,
    text: std.ArrayList(Text) = .empty,
    heap_url: bool = false, // Whether the URL string has been Heap-allocated

    pub fn deinit(self: *Link, gpa: Allocator) void {
        for (self.text.items) |*text| {
            text.deinit(gpa);
        }
        self.text.deinit(gpa);

        if (self.heap_url and self.url.len > 0) {
            gpa.free(self.url);
        }
        self.* = .{};
    }

    pub fn print(self: Link, depth: u8) void {
        debug.printIndent(depth);
        //debug.print("Link to {s}\n", .{self.url});
        debug.print("Link:\n", .{});
        for (self.text.items) |text| {
            text.print(depth + 1);
        }
    }
};

/// Raw text codespan
pub const Codespan = struct {
    text: []const u8 = "",
    heap_text: bool = false,

    pub fn deinit(self: *Codespan, gpa: Allocator) void {
        if (self.heap_text) {
            gpa.free(self.text);
        }
        self.* = .{};
    }
};

/// Image Link
pub const Image = struct {
    src: []const u8 = "",
    alt: std.ArrayList(Text) = .empty,
    kind: Kind = .local, // Local file, or web URL
    format: Format = .other,
    heap_src: bool = false, // Whether the src string has been heap-allocated

    pub const Format = enum(u8) {
        /// PNG file that can be directly sent to the terminal with the Kitty Graphics Protocol
        png,
        /// JPEG file that can be loaded with stb_image and sent to the terminal as raw RGB pixels
        jpeg,
        /// SVG file that can be converted to a PNG
        svg,
        /// Some other image type we will attempt to load using stb_image
        other,
    };

    pub const Kind = enum(u8) {
        local,
        web,
    };

    pub fn deinit(self: *Image, gpa: Allocator) void {
        for (self.alt.items) |*text| {
            text.deinit(gpa);
        }
        self.alt.deinit(gpa);

        if (self.heap_src and self.src.len > 0)
            gpa.free(self.src);
    }

    pub fn print(self: Image, depth: u8) void {
        debug.printIndent(depth);
        debug.print("Image: {s}\n", .{self.src});
        for (self.alt.items) |text| {
            text.print(depth + 1);
        }
    }
};

/// Auto-link
pub const Autolink = struct {
    url: []const u8 = "",
    heap_url: bool = false, // Whether the url string has been heap-allocated

    pub fn print(self: Autolink, depth: u8) void {
        debug.printIndent(depth);
        debug.print("Autolink: {s}\n", .{self.url});
    }

    pub fn deinit(self: *Autolink, gpa: Allocator) void {
        if (self.heap_url and self.url.len > 0) {
            gpa.free(self.url);
        }
    }
};
