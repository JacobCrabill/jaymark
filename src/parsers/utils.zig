const std = @import("std");

const utils = @import("../utils.zig");
const toks = @import("../tokens.zig");
const blocks = @import("../ast/blocks.zig");
const containers = @import("../ast/containers.zig");
const leaves = @import("../ast/leaves.zig");
const inls = @import("../ast/inlines.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const TokenType = toks.TokenType;
const Token = toks.Token;
const TokenList = toks.TokenList;

const TextStyle = inls.TextStyle;
const Text = inls.Text;
const Inline = inls.Inline;
const InlineData = inls.InlineData;

const debug = @import("../debug.zig");
const errorReturn = debug.errorReturn;
const errorMsg = debug.errorMsg;

/// Options to configure the Parsers
pub const ParserOpts = struct {
    /// Allocate a copy of the input text (Caller may free input after creating Parser)
    copy_input: bool = false,
    /// Fully log the output of parser to the console
    verbose: bool = false,
};

///////////////////////////////////////////////////////////////////////////////
// Helper Functions
///////////////////////////////////////////////////////////////////////////////

/// Count the number of leading spaces in the given line
pub fn countLeadingWhitespace(line: []const Token) usize {
    var leading_ws: usize = 0;
    for (line) |tok| {
        switch (tok.kind) {
            .space => leading_ws += 1,
            .indent => leading_ws += 2,
            else => return leading_ws,
        }
    }
    return 0;
}

/// Remove all leading whitespace (spaces or indents) from the start of a line
pub fn trimLeadingWhitespace(line: []const Token) []const Token {
    if (line.len == 0) return line;
    var start: usize = line.len - 1;
    for (line, 0..) |tok, i| {
        if (!(tok.kind == .space or tok.kind == .indent)) {
            start = i;
            break;
        }
    }
    return line[start..];
}

/// Remove all trailing whitespace (space, indent, or line break) from the end of a line
pub fn trimTrailingWhitespace(line: []const Token) []const Token {
    if (line.len == 0) return line;
    var i: usize = line.len;
    var end: usize = 0;
    while (i > 0) : (i -= 1) {
        const tok = line[i - 1];
        switch (tok.kind) {
            .space, .indent, .newline => {},
            else => {
                end = i;
                break;
            },
        }
    }
    return line[0..end];
}

/// Remove up to max_ws leading whitespace characters from the start of the line
pub fn removeIndent(line: []const Token, max_ws: usize) []const Token {
    var start: usize = 0;
    var ws_count: usize = 0;
    for (line, 0..) |tok, i| {
        switch (tok.kind) {
            .space => {
                ws_count += 1;
                if (ws_count > max_ws) {
                    start = i;
                    break;
                }
            },
            .indent => {
                ws_count += 2;
                if (ws_count > max_ws) {
                    start = i;
                    break;
                }
            },
            else => {
                start = i;
                break;
            },
        }
    }
    start = @min(start, max_ws);
    return line[@min(max_ws, start)..];
}

/// Find the index of the next token of any of type 'kind' at or beyond 'idx'
pub fn findFirstOf(tokens: []const Token, idx: usize, kinds: []const TokenType) ?usize {
    var i: usize = idx;
    while (i < tokens.len) : (i += 1) {
        if (std.mem.indexOfScalar(TokenType, kinds, tokens[i].kind)) |_| {
            return i;
        }
    }
    return null;
}

/// Return the index of the next BREAK token, or EOF
pub fn nextBreak(tokens: []const Token, idx: usize) usize {
    if (idx >= tokens.len)
        return tokens.len;

    for (tokens[idx..], idx..) |tok, i| {
        if (tok.kind == .newline)
            return i;
    }

    return tokens.len;
}

/// Return a slice of the tokens from the start index to the next line break (or EOF)
pub fn getLine(tokens: []const Token, start: usize) ?[]const Token {
    if (start >= tokens.len) return null;
    const end = @min(nextBreak(tokens, start) + 1, tokens.len);
    return tokens[start..end];
}

pub fn isEmptyLine(line: []const Token) bool {
    if (line.len == 0 or line[0].kind == .newline)
        return true;

    return false;
}

pub fn isWhitespace(kind: TokenType) bool {
    return switch (kind) {
        .space, .indent, .newline => true,
        else => false,
    };
}

/// Find the column of the first non-whitespace token
pub fn findStartColumn(line: []const Token) usize {
    for (line) |tok| {
        if (isWhitespace(tok.kind))
            continue;
        return tok.src.col;
    }
    return 0;
}

/// Check for the pattern "[ ]*[0-9]*[.][ ]+"
pub fn isOrderedListItem(line: []const Token) bool {
    var have_period: bool = false;
    var have_digit: bool = false;
    for (trimLeadingWhitespace(line)) |tok| {
        switch (tok.kind) {
            .digit => {
                if (have_period) return false;
                have_digit = true;
            },
            .period => {
                if (!have_digit) return false;
                have_period = true;
            },
            .space, .indent, .newline => {
                if (have_period) return true;
                return false;
            },
            else => return false,
        }
    }

    return false;
}

/// Check for the pattern "[ ]*[-+*][ ]+"
pub fn isUnorderedListItem(line: []const Token) bool {
    var have_bullet: bool = false;
    for (trimLeadingWhitespace(line)) |tok| {
        switch (tok.kind) {
            .space, .indent, .newline => {
                if (have_bullet) return true;
                return false;
            },
            .plus, .minus, .star => {
                if (have_bullet and tok.kind != .star) return false; // Can only have one bullet character
                have_bullet = true;
            },
            else => return false,
        }
    }

    return false;
}

/// Check for the pattern like "- [ ]" or "- [x]"
pub fn isTaskListItem(line: []const Token) bool {
    return taskListLeadIdx(line) != null;
}

/// Find the index of the Token following the task list item leaders
pub fn taskListLeadIdx(line: []const Token) ?usize {
    const State = enum {
        start,
        have_bullet,
        have_lbrack,
        have_check,
        have_rbrack,
        have_space,
    };

    var state: State = .start;
    for (line, 0..) |tok, i| {
        switch (state) {
            .start => {
                switch (tok.kind) {
                    .plus, .minus, .star => state = .have_bullet,
                    .space, .indent => {},
                    else => return null,
                }
            },
            .have_bullet => {
                switch (tok.kind) {
                    .lbrack => state = .have_lbrack,
                    .space, .indent => {},
                    else => return null,
                }
            },
            .have_lbrack => {
                switch (tok.kind) {
                    .rbrack => state = .have_rbrack,
                    .space, .indent => {},
                    .word => {
                        // We only allow a single character inside the '[]'
                        if (tok.text.len == 1) {
                            state = .have_check;
                        } else {
                            return null;
                        }
                    },
                    else => return null,
                }
            },
            .have_check => {
                switch (tok.kind) {
                    .rbrack => state = .have_rbrack,
                    .space, .indent => {},
                    else => return null,
                }
            },
            .have_rbrack => {
                switch (tok.kind) {
                    .space, .indent => state = .have_space,
                    else => return null,
                }
            },
            .have_space => return i,
        }
    }

    return null;
}

/// Check if the task list item is checked or not
/// 'leaders' must contain a valid task list start, e.g. '- [ ]'
pub fn isCheckedTaskListItem(leaders: []const Token) bool {
    for (leaders, 0..) |tok, i| {
        if (tok.kind == .lbrack and i < leaders.len - 1) {
            if (leaders[i + 1].kind == .word)
                return true;
            return false;
        }
    }
    return false;
}

/// Check for any kind of list item
pub fn isListItem(line: []const Token) bool {
    return isUnorderedListItem(line) or isOrderedListItem(line);
}

/// Check if the line starts a table row (begins with '|' and has at least '||')
pub fn isTableRow(line: []const Token) bool {
    const trimmed = trimLeadingWhitespace(line);
    if (trimmed.len == 0) return false;
    if (trimmed[0].kind != .pipe) return false;
    return countKind(trimmed, .pipe) >= 2;
}

/// Check for the pattern "[ ]*[>][ ]+"
pub fn isQuote(line: []const Token) bool {
    var have_caret: bool = false;
    for (trimLeadingWhitespace(line)) |tok| {
        switch (tok.kind) {
            .gt => {
                if (have_caret) return false;
                have_caret = true;
            },
            .space, .indent => {
                if (have_caret) return true;
            },
            else => return false,
        }
    }

    return false;
}

/// Check for the pattern "[ ]*[#]+[ ]+"
pub fn isHeading(line: []const Token) bool {
    var have_hash: bool = false;
    for (trimLeadingWhitespace(line)) |tok| {
        switch (tok.kind) {
            .hash => {
                have_hash = true;
            },
            .space, .indent => {
                if (have_hash) return true;
            },
            else => return false,
        }
    }

    return false;
}

pub fn isCodeBlock(line: []const Token) bool {
    for (line) |tok| {
        switch (tok.kind) {
            .directive => return true,
            .space, .indent => {},
            else => return false,
        }
    }

    return false;
}

/// Check for a Github Flavored Markdown Alert like "> [!INFO]\n".
/// https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts
pub fn isGithubAlert(line: []const Token) bool {
    const tline = trimLeadingWhitespace(trimTrailingWhitespace(line));
    if (tline.len != 6) return false;

    if (tline[0].kind != .gt) return false;
    if (!(tline[1].kind == .space or tline[1].kind == .indent))
        return false;
    if (tline[2].kind != .lbrack) return false;
    if (tline[3].kind != .bang) return false;
    if (tline[4].kind != .word) return false;
    if (tline[5].kind != .rbrack) return false;

    return true;
}

test isGithubAlert {
    const is_alert: []const Token = &.{
        .{ .kind = .gt, .text = ">" },
        .{ .kind = .space, .text = " " },
        .{ .kind = .lbrack, .text = "[" },
        .{ .kind = .bang, .text = "!" },
        .{ .kind = .word, .text = "INFO" },
        .{ .kind = .rbrack, .text = "]" },
        .{ .kind = .newline, .text = "\n" },
    };
    try std.testing.expect(isGithubAlert(is_alert));

    const not_alert1: []const Token = &.{
        .{ .kind = .gt, .text = ">" },
        .{ .kind = .space, .text = " " },
        .{ .kind = .bang, .text = "!" },
        .{ .kind = .word, .text = "INFO" },
        .{ .kind = .newline, .text = "\n" },
    };
    try std.testing.expect(!isGithubAlert(not_alert1));

    // Note: `![...]` is incorrect; `[!...]` is correct
    const not_alert2: []const Token = &.{
        .{ .kind = .gt, .text = ">" },
        .{ .kind = .space, .text = " " },
        .{ .kind = .bang, .text = "!" },
        .{ .kind = .lbrack, .text = "[" },
        .{ .kind = .word, .text = "INFO" },
        .{ .kind = .rbrack, .text = "]" },
        .{ .kind = .newline, .text = "\n" },
    };
    try std.testing.expect(!isGithubAlert(not_alert2));
}

/// Concatenate a list of raw token text into a single string
pub fn concatRawText(alloc: Allocator, tok_words: ArrayList(Token)) Allocator.Error![]const u8 {
    if (tok_words.items.len > 0) {
        // Extract *just* the text of each token into a new array
        var words: ArrayList([]const u8) = .empty;
        defer words.deinit(alloc);
        for (tok_words.items) |word| {
            try words.append(alloc, word.text);
        }

        // Merge all words into a single string, merging consecutive whitespace
        const new_text: []u8 = try std.mem.concat(alloc, u8, words.items);
        defer alloc.free(new_text);
        const new_text_ws = std.mem.collapseRepeats(u8, new_text, ' ');
        return try alloc.dupe(u8, new_text_ws);
    }
    return try alloc.dupe(u8, "null");
}

/// Append a list of words to the given TextBlock as Text objects
pub fn appendText(alloc: Allocator, text_parts: *ArrayList(Text), words: *ArrayList([]const u8), style: TextStyle) Allocator.Error!void {
    if (words.items.len > 0) {
        // Merge all words into a single string, merging consecutive whitespace
        const new_text: []u8 = try std.mem.concat(alloc, u8, words.items);
        defer alloc.free(new_text);
        const new_text_ws = std.mem.collapseRepeats(u8, new_text, ' ');

        // End the current Text object with the current style
        const text = Text{
            .style = style,
            .text = try alloc.dupe(u8, new_text_ws),
            .heap_text = true,
        };
        try text_parts.append(alloc, text);
        words.clearRetainingCapacity();
    }
}

/// Append a list of words to the given TextBlock as Text objects, preserving position information
pub fn appendTextWithPos(alloc: Allocator, text_parts: *ArrayList(Text), tokens: []const Token, start: usize, end: usize, style: TextStyle) Allocator.Error!void {
    if (start < end and start < tokens.len) {
        var words: ArrayList([]const u8) = .empty;
        defer words.deinit(alloc);

        for (tokens[start..end]) |tok| {
            try words.append(alloc, tok.text);
        }

        // Merge all words into a single string, merging consecutive whitespace
        const new_text: []u8 = try std.mem.concat(alloc, u8, words.items);
        defer alloc.free(new_text);
        const new_text_ws = std.mem.collapseRepeats(u8, new_text, ' ');

        // End the current Text object with the current style and position info
        const text = Text{
            .style = style,
            .text = try alloc.dupe(u8, new_text_ws),
            .heap_text = true,
            .line = tokens[start].src.row,
            .col = tokens[start].src.col,
        };
        try text_parts.append(alloc, text);
    }
}

/// Append a list of words to the given TextBlock as Inline Text objects
pub fn appendWords(alloc: Allocator, inlines: *ArrayList(Inline), words: *ArrayList([]const u8), style: TextStyle) Allocator.Error!void {
    if (words.items.len > 0) {
        // Merge all words into a single string
        // Merge duplicate ' ' characters
        const new_text: []u8 = try std.mem.concat(alloc, u8, words.items);
        defer alloc.free(new_text);
        const new_text_ws = std.mem.collapseRepeats(u8, new_text, ' ');

        // End the current Text object with the current style
        const text = Text{
            .style = style,
            .text = try alloc.dupe(u8, new_text_ws),
            .heap_text = true,
        };
        try inlines.append(alloc, Inline.initWithContent(.{ .text = text }));
        words.clearRetainingCapacity();
    }
}

/// Append a list of tokens to the given inlines list as Inline Text objects, preserving position information
pub fn appendWordsWithPos(alloc: Allocator, inlines: *ArrayList(Inline), tokens: []const Token, start: usize, end: usize, style: TextStyle) Allocator.Error!void {
    if (start < end and start < tokens.len) {
        var words: ArrayList([]const u8) = .empty;
        defer words.deinit(alloc);

        for (tokens[start..end]) |tok| {
            try words.append(alloc, tok.text);
        }

        // Merge all words into a single string
        // Merge duplicate ' ' characters
        const new_text: []u8 = try std.mem.concat(alloc, u8, words.items);
        defer alloc.free(new_text);
        const new_text_ws = std.mem.collapseRepeats(u8, new_text, ' ');

        // End the current Text object with the current style and position info
        const text = Text{
            .style = style,
            .text = try alloc.dupe(u8, new_text_ws),
            .heap_text = true,
            .line = tokens[start].src.row,
            .col = tokens[start].src.col,
        };
        try inlines.append(alloc, Inline.initWithContent(.{ .text = text }));
    }
}

/// Append a single token as an Inline Text object, preserving position information
pub fn appendSingleToken(alloc: Allocator, inlines: *ArrayList(Inline), token: Token, style: TextStyle) Allocator.Error!void {
    const text = Text{
        .style = style,
        .text = try alloc.dupe(u8, utils.trimLeadingWhitespace(token.text)),
        .heap_text = true,
        .line = token.src.row,
        .col = token.src.col,
    };
    try inlines.append(alloc, Inline.initWithContent(.{ .text = text }));
}

/// Check if the token slice contains a valid link of the form: [text](url).
/// TODO: Return ?LinkParts containing indices of '[', ']', '(', ')'.
/// TODO: Handle escaped characters and inline code (e.g. "`]`" or "\]")
pub fn validateLink(in_line: []const Token) bool {
    const line: []const Token = getLine(in_line, 0) orelse return false;
    if (line[0].kind != .lbrack) return false;

    // Find the ']' corresponding to the first '['
    const rb_idx: usize = blk: {
        var bcount: i32 = 0;
        for (line, 0..) |tok, i| {
            switch (tok.kind) {
                .rbrack => bcount -= 1,
                .lbrack => bcount += 1,
                else => {},
            }
            if (bcount == 0) break :blk @intCast(i);
        }
        // This is an error.
        break :blk 0;
    };
    if (rb_idx <= 0 or rb_idx + 2 >= line.len) return false;

    // Check that the next character is '('
    if (line[rb_idx + 1].kind != .lparen) return false;

    // Find the matching ')', accounting for nested "()"
    const rp_idx: usize = blk: {
        var pcount: i32 = 1; // Start with one '(' immediately behind us
        for (line[rb_idx + 2 ..], rb_idx + 2..) |tok, i| {
            switch (tok.kind) {
                .rparen => pcount -= 1,
                .lparen => pcount += 1,
                else => {},
            }
            if (pcount == 0) break :blk @intCast(i);
        }
        // This is an error.
        break :blk 0;
    };
    if (rp_idx <= rb_idx + 1) return false;

    return true;
}

test validateLink {
    const TestData = struct {
        link: []const u8,
        valid: bool,
    };

    // TODO: There are more rules about what constitutes a valid link
    const test_data: []const TestData = &.{
        .{ .link = "[]()", .valid = true },
        .{ .link = "[foo](bar)", .valid = true },
        .{ .link = "[foo (bar)](bar (baz))", .valid = true },
        .{ .link = "[()", .valid = false },
        .{ .link = "[])", .valid = false },
        .{ .link = "[](", .valid = false },
        .{ .link = "]()", .valid = false },
        .{ .link = "[[]()", .valid = false },
        .{ .link = "[](()", .valid = false },
        .{ .link = "[foo\\](`bar)", .valid = false },
        // FIXME: These should NOT be valid, but currently are
        .{ .link = "[foo`](`bar)", .valid = true },
    };

    const Lexer = @import("../lexer.zig").Lexer;

    for (test_data) |data| {
        var lex = Lexer{};
        var tokens = try lex.tokenize(std.testing.allocator, data.link);
        defer tokens.deinit(std.testing.allocator);

        try std.testing.expectEqual(validateLink(tokens.items), data.valid);
    }
}

/// Count all instances of the 'kind' token in the given line,
/// ignoring any tokens within an inline code span.
pub fn countKind(line: []const Token, kind: TokenType) usize {
    var count: usize = 0;
    var in_code: bool = false;
    for (line) |tok| {
        if (tok.kind == .code_inline) in_code = !in_code;
        if (tok.kind == kind and !in_code) count += 1;
    }
    return count;
}

/// Find the index of the first occurance of a 'kind' Token beginning from 'start_index' (inclusive).
///
/// Skips tokens inside an inline code span.
///
/// The index is relative to the start of the 'line' slice.
pub fn indexOfTokenPos(line: []const Token, start_index: usize, kind: TokenType) ?usize {
    var in_code: bool = false;
    for (line[start_index..], start_index..) |tok, i| {
        if (tok.kind == .code_inline) in_code = !in_code;
        if (tok.kind == kind and !in_code) return i;
    }
    return null;
}
