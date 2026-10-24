/// Defines all possible Markdown tokens used by Jaymark.
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const utils = @import("utils.zig");
const debug = @import("debug.zig");

// zig fmt: off
pub const TokenType = enum {
    eof, word, digit, indent, space, newline,
    hash, directive, code_inline,
    plus, minus, star, dollar, uscore, colon,
    tilde, period, comma, equal, bang, query, at,
    percent, caret, ampersand, lt, gt,
    lparen, rparen, lbrack, rbrack, lcurly, rcurly,
    slash, bslash, pipe, bold, embold,
    escaped, unknown,
};
// zig fmt: on

pub const SourceLocation = struct {
    row: usize = 0,
    col: usize = 0,
};

pub const Token = struct {
    kind: TokenType = TokenType.eof,
    text: []const u8 = undefined,
    src: SourceLocation = undefined,
};

pub const TokenList = ArrayList(Token);

pub const Eof = Token{ .kind = .eof, .text = "" };

/// For future use with parsing obscure syntax in links
const Precedence = enum(u8) {
    lowest,
    emphasis,
    bracket,
    tick,
    bslash,
};

/// Generic parser for a multi-character token from a list of possible characters
/// Greedily accepts as many characters as it can
pub fn AnyOfTokenizer(comptime chars: []const u8, comptime kind: TokenType) type {
    return struct {
        pub fn peek(text: []const u8) ?Token {
            if (text.len == 0)
                return null;

            var i: usize = 0;
            while (i < text.len and std.mem.indexOfScalar(u8, chars, text[i]) != null) : (i += 1) {}
            if (i == 0) return null;
            return Token{
                .kind = kind,
                .text = text[0..i],
            };
        }
    };
}

/// Generic parser for single-character tokens
/// Parse the u8 'char' as token type 'kind'
pub fn SingularTokenizer(comptime char: u8, comptime kind: TokenType) type {
    return struct {
        pub fn peek(text: []const u8) ?Token {
            if (text.len > 0 and text[0] == char) {
                return Token{
                    .kind = kind,
                    .text = text[0..1],
                };
            }
            return null;
        }
    };
}

/// Generic parser for multi-character literals
pub fn LiteralTokenizer(comptime delim: []const u8, comptime kind: TokenType) type {
    return struct {
        pub fn peek(text: []const u8) ?Token {
            if (text.len >= delim.len and std.mem.startsWith(u8, text, delim)) {
                return Token{
                    .kind = kind,
                    .text = text[0..delim.len],
                };
            }

            return null;
        }
    };
}

/// Parser for a generic word.
/// Note that we must check for unicode (non-ASCII) characters which are simply
/// codepoints such as 'ä' and should be treated as generic characters.
pub const WordTokenizer = struct {
    pub fn peek(text: []const u8) ?Token {
        var end = text.len;
        var i: usize = 0;
        while (i < text.len) : (i += 1) {
            const c = text[i];

            if (std.ascii.isWhitespace(c) or utils.isPunctuation(c)) {
                end = i;
                break;
            }

            // Check for a multi-byte utf-8 codepoint. Skip ahead the appropriate number of bytes.
            if (std.unicode.utf8ByteSequenceLength(c)) |len| {
                i += len - 1;
            } else |_| {}
        }

        if (end > 0) {
            return Token{
                .kind = TokenType.word,
                .text = text[0..end],
            };
        }

        return null;
    }
};

/// Parser for a directive token
pub const DirectiveTokenizer = struct {
    pub fn peek(text: []const u8) ?Token {
        if (text.len == 0) return null;

        var end: usize = 0;
        for (text) |c| {
            if (c != '`') break;
            end += 1;
        }

        // We only match 3 or more '`' characters
        if (end > 2) {
            return Token{
                .kind = TokenType.directive,
                .text = text[0..end],
            };
        }

        return null;
    }
};

/// Matches a backslash followed by any ASCII punctuation character.
/// Produces an ESCAPED token whose .text is the two-character sequence (e.g. "\|").
/// This allows downstream parsers to treat the following character as literal text
/// rather than as a structural delimiter.
pub const EscapeTokenizer = struct {
    pub fn peek(text: []const u8) ?Token {
        if (text.len < 2 or text[0] != '\\') return null;
        const next = text[1];
        if (!utils.isPunctuation(next)) return null;
        return Token{
            .kind = .escaped,
            .text = text[0..2],
        };
    }
};

/// Handles multi-byte unicode codepoints.
///
/// If we DO encounter a >1-byte (non-ASCII) codepoint, we will assume it is
/// simply a character starting a Word, and handle it as such.
pub const Utf8Tokenizer = struct {
    pub fn peek(text: []const u8) ?Token {
        if (std.unicode.utf8ByteSequenceLength(text[0])) |len| {
            if (len == 1) return null;
        } else |_| return null;

        return WordTokenizer.peek(text);
    }
};

/// Collect all available tokenizers
pub const Tokenizers = .{
    Utf8Tokenizer,
    LiteralTokenizer("\r\n", TokenType.newline),
    LiteralTokenizer("\n", TokenType.newline),
    LiteralTokenizer("\t", TokenType.indent),
    LiteralTokenizer("***", TokenType.embold),
    LiteralTokenizer("_**", TokenType.embold),
    LiteralTokenizer("**_", TokenType.embold),
    LiteralTokenizer("*__", TokenType.embold),
    LiteralTokenizer("__*", TokenType.embold),
    LiteralTokenizer("___", TokenType.embold),
    LiteralTokenizer("**", TokenType.bold),
    LiteralTokenizer("__", TokenType.bold),
    DirectiveTokenizer,
    SingularTokenizer('`', TokenType.code_inline),
    SingularTokenizer(' ', TokenType.space),
    SingularTokenizer('#', TokenType.hash),
    SingularTokenizer('*', TokenType.star),
    SingularTokenizer('_', TokenType.uscore),
    SingularTokenizer('~', TokenType.tilde),
    SingularTokenizer('+', TokenType.plus),
    SingularTokenizer('-', TokenType.minus),
    SingularTokenizer('<', TokenType.lt),
    SingularTokenizer('>', TokenType.gt),
    SingularTokenizer('.', TokenType.period),
    SingularTokenizer(',', TokenType.comma),
    SingularTokenizer('=', TokenType.equal),
    SingularTokenizer('!', TokenType.bang),
    SingularTokenizer('?', TokenType.query),
    SingularTokenizer('@', TokenType.at),
    SingularTokenizer('$', TokenType.dollar),
    SingularTokenizer('%', TokenType.percent),
    SingularTokenizer('^', TokenType.caret),
    SingularTokenizer('&', TokenType.ampersand),
    SingularTokenizer('(', TokenType.lparen),
    SingularTokenizer(')', TokenType.rparen),
    SingularTokenizer('[', TokenType.lbrack),
    SingularTokenizer(']', TokenType.rbrack),
    SingularTokenizer('{', TokenType.lcurly),
    SingularTokenizer('}', TokenType.rcurly),
    SingularTokenizer('/', TokenType.slash),
    EscapeTokenizer,
    SingularTokenizer('\\', TokenType.bslash),
    SingularTokenizer('|', TokenType.pipe),
    SingularTokenizer(':', TokenType.colon),
    AnyOfTokenizer("0123456789", TokenType.digit),
    WordTokenizer,
};

///////////////////////////////////////////////////////////////////////////////
// Utility Functions
///////////////////////////////////////////////////////////////////////////////

pub fn printTypes(tokens: []const Token) void {
    for (tokens) |tok| {
        debug.print("{t}, ", .{tok.kind});
    }
    debug.print("\n", .{});
}

pub fn printText(tokens: []const Token) void {
    debug.print("\"", .{});
    for (tokens) |tok| {
        if (tok.kind == .newline) {
            debug.print("\\n", .{});
            continue;
        }
        debug.print("{s}", .{tok.text});
    }
    debug.print("\"\n", .{});
}

/// Concatenate the raw text of each token into a single string
pub fn concatWords(alloc: Allocator, tokens: []const Token) ![]const u8 {
    var words = try ArrayList([]const u8).initCapacity(alloc, tokens.len);
    defer words.deinit(alloc);

    for (tokens) |tok| {
        try words.append(alloc, tok.text);
    }

    return try std.mem.concat(alloc, u8, words.items);
}

///////////////////////////////////////////////////////////////////////////////
// Tests
///////////////////////////////////////////////////////////////////////////////

test "EscapeTokenizer: backslash-pipe produces escaped token" {
    const tok = EscapeTokenizer.peek("\\|rest").?;
    try std.testing.expectEqual(TokenType.escaped, tok.kind);
    try std.testing.expectEqualStrings("\\|", tok.text);
}

test "EscapeTokenizer: lone backslash does not produce escaped token" {
    try std.testing.expect(EscapeTokenizer.peek("\\") == null);
}

test "EscapeTokenizer: backslash-letter does not produce escaped token" {
    try std.testing.expect(EscapeTokenizer.peek("\\n") == null);
}
