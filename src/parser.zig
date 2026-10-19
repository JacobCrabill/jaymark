pub const ParserOpts = @import("parsers/utils.zig").ParserOpts;
pub const Parser = @import("parsers/blocks.zig").Parser;
pub const InlineParser = @import("parsers/inlines.zig").InlineParser;

/// Parse a file to its Markdown AST representation.
///
/// io: Io implementation to use to load the file from the filesystem.
/// gpa: General purpose allocator for all allocations.
/// dir: The directory containing the file.
/// path: The filepath to the Markdown file relative to `dir`.
///
/// Returns the parsed document Block.
pub fn parseFile(io: std.Io, gpa: std.mem.Allocator, dir: std.Io.Dir, path: []const u8) !Block {
    const contents = try utils.readFile(io, gpa, dir, path);
    defer gpa.free(contents);
    return try parse(gpa, contents);
}

/// Parse a file to its Markdown AST representation.
///
/// gpa: General purpose allocator for all allocations.
/// contents: The raw Markdown file contents to parse.
///
/// Returns the parsed document Block.
pub fn parse(gpa: std.mem.Allocator, contents: []const u8) !Block {
    var p = Parser.init(gpa, .{});
    defer p.deinit();
    try p.parseMarkdown(contents);
    return try p.toOwnedDocument();
}

//////////////////////////////////////////////////////////
// Tests
//////////////////////////////////////////////////////////

test "All Parser Tests" {
    @import("std").testing.refAllDecls(@This());
}

const std = @import("std");
const utils = @import("utils.zig");

const Block = @import("ast/blocks.zig").Block;
