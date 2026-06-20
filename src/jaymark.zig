//! Zigdown: Markdown Toolset in Zig.
//!
//! This module exposes the entire Zigdown package,
//! including all of its dependencies.

// Expose dependencies to downstream consumers
pub const stbi = @import("stb_image");
pub const flags = @import("flags");

// Expose public namespaces for building docs
pub const debug = @import("debug.zig");
pub const lexer = @import("lexer.zig");
pub const parser = @import("parser.zig");
pub const tokens = @import("tokens.zig");
pub const utils = @import("utils.zig");
pub const blocks = @import("ast/blocks.zig");

// Global public Zigdown types
// pub const Markdown = markdown.Markdown;
pub const Block = blocks.Block;
pub const Container = blocks.Container;
pub const Leaf = blocks.Leaf;
pub const Token = tokens.Token;
pub const TokenType = tokens.TokenType;
pub const Parser = parser.Parser;
pub const Lexer = lexer.Lexer;
