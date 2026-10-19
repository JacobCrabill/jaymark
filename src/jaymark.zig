//! Jaymark: Markdown Toolset in Zig.
//!
//! This module exposes the entire Jaymark package,
//! including all of its dependencies.

// Expose public namespaces for building docs
pub const debug = @import("debug.zig");
pub const lexer = @import("lexer.zig");
pub const parser = @import("parser.zig");
pub const tokens = @import("tokens.zig");
pub const utils = @import("utils.zig");
pub const blocks = @import("ast/blocks.zig");
pub const containers = @import("ast/containers.zig");
pub const inlines = @import("ast/inlines.zig");
pub const leaves = @import("ast/leaves.zig");
pub const formatter = @import("formatter.zig");

// Global public Jaymark types
// pub const Markdown = markdown.Markdown;
pub const Block = blocks.Block;
pub const Container = blocks.Container;
pub const Leaf = blocks.Leaf;
pub const Token = tokens.Token;
pub const TokenType = tokens.TokenType;
pub const Parser = parser.Parser;
pub const ParserOpts = parser.ParserOpts;
pub const Lexer = lexer.Lexer;
pub const Formatter = formatter.Formatter;

/// Parse a file to its Markdown AST representation.
///
/// io: Io implementation to use to load the file from the filesystem.
/// gpa: General purpose allocator for all allocations.
/// dir: The directory containing the file.
/// path: The filepath to the Markdown file relative to `dir`.
///
/// Returns the parsed document Block.
pub fn parseFile(io: std.Io, gpa: std.mem.Allocator, dir: std.Io.Dir, path: []const u8) !Block {
    return try parser.parseFile(io, gpa, dir, path);
}

/// Parse a file to its Markdown AST representation.
///
/// gpa: General purpose allocator for all allocations.
/// contents: The raw Markdown file contents to parse.
///
/// Returns the parsed document Block.
pub fn parse(gpa: std.mem.Allocator, contents: []const u8) !Block {
    return try parser.parse(gpa, contents);
}

pub const ParseResult = struct { time_s: f64, document: Block };

/// Parse a Markdown file and return the time taken and the Parser object
///
/// io: The Io instance to use for timing.
/// gpa: General purpose allocator for all allocations.
/// contents: The raw Markdown file contents to parse.
///
/// Returns the parser used to parse the document, and the time taken for the parsing.
pub fn timedParse(io: std.Io, gpa: std.mem.Allocator, input: []const u8, verbose: bool) !ParseResult {
    var p = Parser.init(gpa, .{ .copy_input = false, .verbose = verbose });
    defer p.deinit();

    var ptimer = @import("utils.zig").Timer.start(io);
    try p.parseMarkdown(input);
    const ptime_s = ptimer.read();

    if (verbose) {
        debug.print("AST:\n", .{});
        p.document.print(0);
    }

    return .{ .time_s = ptime_s, .document = try p.toOwnedDocument() };
}

/// Format a Markdown document.
///
/// io: The Io instance to use.
/// gpa: General purpose allocator for all allocations.
/// contents: The raw Markdown file contents to format.
/// width: The width at which to line-wrap the output.
///
/// The returned slice is backed by the given allocator.
pub fn format(io: std.Io, gpa: std.mem.Allocator, contents: []const u8, width: usize) ![]const u8 {
    var doc = try parse(gpa, contents);
    defer doc.deinit();

    var f = Formatter.init(io, gpa, .{ .width = width });
    defer f.deinit();

    return try f.format(doc);
}

/// Format a Markdown document.
///
/// io: The Io instance to use.
/// gpa: General purpose allocator for all allocations.
/// contents: The raw Markdown file contents to format.
/// width: The width at which to line-wrap the output.
///
/// The returned slice is backed by the given allocator.
pub fn formatFile(io: std.Io, gpa: std.mem.Allocator, dir: std.Io.Dir, path: []const u8, width: usize) ![]const u8 {
    var doc = try parseFile(io, gpa, dir, path);
    defer doc.deinit();

    var f = Formatter.init(io, gpa, .{ .width = width });
    defer f.deinit();

    return try f.format(doc);
}

test "All Tests" {
    std.testing.refAllDecls(@This());
}

test format {
    const gpa = std.testing.allocator;

    const input = " #   Hello!  ";
    const expected = "# Hello!\n";

    const actual = try format(std.testing.io, gpa, input, 90);
    defer gpa.free(actual);

    try std.testing.expectEqualSlices(u8, expected, actual);
}

const std = @import("std");
