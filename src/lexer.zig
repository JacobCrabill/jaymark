/// lexer.zig
/// Markdown lexer. Processes Markdown text into a list of tokens.
const std = @import("std");

const debug = @import("debug.zig");
const toks = @import("tokens.zig");
const utils = @import("utils.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const GPA = std.heap.GeneralPurposeAllocator;

/// Common types from the Jaymark namespace
const TokenType = toks.TokenType;
const Token = toks.Token;
const TokenList = toks.TokenList;

/// Convert Markdown text into a stream of tokens
pub const Lexer = struct {
    data: []const u8 = undefined,
    cursor: usize = 0,
    src: toks.SourceLocation = toks.SourceLocation{},

    /// Store the text and reset the cursor position
    pub fn setText(self: *Lexer, text: []const u8) void {
        self.data = text;
        self.cursor = 0;
    }

    /// Tokenize the given input text
    pub fn tokenize(self: *Lexer, alloc: Allocator, text: []const u8) !ArrayList(Token) {
        self.setText(text);

        var tokens: ArrayList(Token) = .empty;
        var token = self.next();
        try tokens.append(alloc, token);
        while (token.kind != .eof) {
            token = self.next();
            try tokens.append(alloc, token);
        }
        return tokens;
    }

    /// Consume the remainder of the current line and return if a newline was found
    pub fn eatLine(self: *Lexer) bool {
        const end_opt: ?usize = std.mem.indexOfScalarPos(u8, self.data, self.cursor, '\n');
        if (end_opt) |end| {
            self.cursor = end + 1;
            self.row.row += 1;
            self.src.col = 0;
            return true;
        } else {
            self.cursor = self.data.len;
            return false;
        }
    }

    /// Consume the next token in the text
    pub fn next(self: *Lexer) Token {
        if (self.cursor > self.data.len) {
            return toks.Eof;
        } else if (self.cursor == self.data.len) {
            self.cursor += 1;
            self.src.col += 1;
            return toks.Eof;
        }

        // Apply each of our tokenizers to the current text
        inline for (toks.Tokenizers) |tokenizer| {
            const text = self.data[self.cursor..];
            if (tokenizer.peek(text)) |token| {
                self.cursor += token.text.len;

                const tok = Token{
                    .kind = token.kind,
                    .text = token.text,
                    .src = self.src,
                };

                if (token.kind == .newline) {
                    self.src.row += 1;
                    self.src.col = 0;
                } else {
                    self.src.col += token.text.len;
                }

                return tok;
            }
        }

        // If all else fails, return UNKNOWN
        const token = Token{
            .kind = .unknown,
            .text = self.data[self.cursor .. self.cursor + 1],
            .src = self.src,
        };
        self.cursor += 1;
        return token;
    }
};

//////////////////////////////////////////////////////////
// Tests
//////////////////////////////////////////////////////////

test "Tokenize" {
    const test_input =
        \\# Heading 1
        \\## Heading Two
        \\
        \\Text _italic_ **bold** ___bold_italic___
        \\~underline~
        \\```
        \\*Ääbc*
        \\\
    ;

    const expected_tokens = [_]Token{
        .{ .kind = .hash, .text = "#" },
        .{ .kind = .space, .text = " " },
        .{ .kind = .word, .text = "Heading" },
        .{ .kind = .space, .text = " " },
        .{ .kind = .digit, .text = "1" },
        .{ .kind = .newline, .text = "\n" },
        .{ .kind = .hash, .text = "#" },
        .{ .kind = .hash, .text = "#" },
        .{ .kind = .space, .text = " " },
        .{ .kind = .word, .text = "Heading" },
        .{ .kind = .space, .text = " " },
        .{ .kind = .word, .text = "Two" },
        .{ .kind = .newline, .text = "\n" },
        .{ .kind = .newline, .text = "\n" },
        .{ .kind = .word, .text = "Text" },
        .{ .kind = .space, .text = " " },
        .{ .kind = .uscore, .text = "_" },
        .{ .kind = .word, .text = "italic" },
        .{ .kind = .uscore, .text = "_" },
        .{ .kind = .space, .text = " " },
        .{ .kind = .bold, .text = "**" },
        .{ .kind = .word, .text = "bold" },
        .{ .kind = .bold, .text = "**" },
        .{ .kind = .space, .text = " " },
        .{ .kind = .embold, .text = "___" },
        .{ .kind = .word, .text = "bold" },
        .{ .kind = .uscore, .text = "_" },
        .{ .kind = .word, .text = "italic" },
        .{ .kind = .embold, .text = "___" },
        .{ .kind = .newline, .text = "\n" },
        .{ .kind = .tilde, .text = "~" },
        .{ .kind = .word, .text = "underline" },
        .{ .kind = .tilde, .text = "~" },
        .{ .kind = .newline, .text = "\n" },
        .{ .kind = .directive, .text = "```" },
        .{ .kind = .newline, .text = "\n" },
        .{ .kind = .star, .text = "*" },
        .{ .kind = .word, .text = "Ääbc" },
        .{ .kind = .star, .text = "*" },
        .{ .kind = .newline, .text = "\n" },
        .{ .kind = .bslash, .text = "\\" },
    };

    var lex = Lexer{};
    lex.setText(test_input);

    for (expected_tokens) |token| {
        try compareTokens(token, lex.next());
    }

    try std.testing.expectEqual(TokenType.eof, lex.next().kind);
}

/// Compare an expected token to a token from the Lexer
fn compareTokens(expected: Token, actual: Token) !void {
    std.testing.expectEqual(expected.kind, actual.kind) catch |err| {
        debug.print("Expected {any} ({s}), got {any} ({s})\n", .{ expected.kind, expected.text, actual.kind, actual.text });
        return err;
    };

    std.testing.expect(std.mem.eql(u8, expected.text, actual.text)) catch |err| {
        debug.print("Expected '{s}', got '{s}'\n", .{ expected.text, actual.text });
        return err;
    };
}

test "Lexer: escaped pipe tokenizes as escaped" {
    const lexer = @import("lexer.zig");
    var lex = lexer.Lexer{};
    var tokens = try lex.tokenize(std.testing.allocator, "\\|");
    defer tokens.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), tokens.items.len); // escaped + eof
    try std.testing.expectEqual(TokenType.escaped, tokens.items[0].kind);
    try std.testing.expectEqualStrings("\\|", tokens.items[0].text);
}

test "Lexer: escaped backslash tokenizes as escaped" {
    const lexer = @import("lexer.zig");
    var lex = lexer.Lexer{};
    var tokens = try lex.tokenize(std.testing.allocator, "\\\\");
    defer tokens.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), tokens.items.len); // escaped + eof
    try std.testing.expectEqual(TokenType.escaped, tokens.items[0].kind);
    try std.testing.expectEqualStrings("\\\\", tokens.items[0].text);
}
