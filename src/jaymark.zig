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

// Global public Jaymark types
// pub const Markdown = markdown.Markdown;
pub const Block = blocks.Block;
pub const Container = blocks.Container;
pub const Leaf = blocks.Leaf;
pub const Token = tokens.Token;
pub const TokenType = tokens.TokenType;
pub const Parser = parser.Parser;
pub const Lexer = lexer.Lexer;

test "All Tests" {
    @import("std").testing.refAllDecls(@This());
}
