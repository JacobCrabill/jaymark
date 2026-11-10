/// Debugging-related functionality such as logging and error reporting.
const std = @import("std");
const builtin = @import("builtin");

const Token = @import("tokens.zig").Token;

/// Global flag for building for WASM or not
pub const is_wasm = switch (@import("builtin").cpu.arch) {
    .wasm32, .wasm64 => true,
    else => false,
};

/// Discarding writer to silently drop all log messages.
/// Useful in WASM environments or other bare-metal envs without libc, stderr, etc.
/// Used as the default writer if none provided.
var discarding_writer: std.Io.Writer.Discarding = .init(&.{});

/// Global debug stream instance.
/// Intended to be set once from main() via init().
var stream: *std.Io.Writer = &discarding_writer.writer;

/// Set the global debug output stream.
///
/// This can be, for example, a buffered writer for use in tests.
pub fn init(out_stream: *std.Io.Writer) void {
    stream = out_stream;
}

/// Write bytes to the debug output stream.
pub fn write(bytes: []const u8) void {
    stream.write(bytes) catch {};
}

/// Print a formatted message to the debug output stream at the 'info' level.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    stream.print(fmt, args) catch {};
}

/// Print a newline to the debug output stream.
pub fn println() void {
    stream.writeAll("\n") catch {};
}

pub fn flush() void {
    stream.flush() catch {};
}

pub fn printIndent(depth: u8) void {
    var i: u8 = 0;
    while (i < depth) : (i += 1) {
        print("│ ", .{});
    }
}

pub fn errorReturn(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) !void {
    // TODO: Styled error printing (ANSI colors when applicable)
    print("{s}-{d}: ERROR: ", .{ src.fn_name, src.line });
    print(fmt, args);
    print("\n", .{});
    return error.ParseError;
}

pub fn errorMsg(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    // TODO: Styled error printing (ANSI colors when applicable)
    print("{s}-{d}: ERROR: ", .{ src.fn_name, src.line });
    print(fmt, args);
    print("\n", .{});
}

/// Helper struct to log debug messages (normal host-cpu logger)
pub const Logger = struct {
    const Self = @This();
    depth: usize = 0,
    enabled: bool = false,

    /// Log a debug message (alias for debug)
    pub fn log(self: Self, comptime fmt: []const u8, args: anytype) void {
        if (self.enabled) {
            self.doIndent();
            self.raw(fmt, args);
        }
    }

    /// Log a debug message
    pub fn debug(self: Self, comptime fmt: []const u8, args: anytype) void {
        if (self.enabled) {
            self.doIndent();
            self.raw(fmt, args);
        }
    }

    /// Log an info message
    pub fn info(self: Self, comptime fmt: []const u8, args: anytype) void {
        if (self.enabled) {
            self.doIndent();
            self.raw(fmt, args);
        }
    }

    /// Log a warning message
    pub fn warn(self: Self, comptime fmt: []const u8, args: anytype) void {
        if (self.enabled) {
            self.doIndent();
            self.raw(fmt, args);
        }
    }

    /// Log an error message
    pub fn err(self: Self, comptime fmt: []const u8, args: anytype) void {
        if (self.enabled) {
            self.doIndent();
            self.raw(fmt, args);
        }
    }

    /// Raw print without indentation or log level prefix
    pub fn raw(self: Self, comptime fmt: []const u8, args: anytype) void {
        if (self.enabled) {
            print(fmt, args);
        }
    }

    pub fn printTypes(self: Self, tokens: []const Token, indent: bool) void {
        if (indent) self.doIndent();
        for (tokens) |tok| {
            self.raw("{s}, ", .{@tagName(tok.kind)});
        }
        self.raw("\n", .{});
    }

    pub fn printText(self: Self, tokens: []const Token, indent: bool) void {
        if (indent) self.doIndent();
        self.raw("\"", .{});
        for (tokens) |tok| {
            if (tok.kind == .newline) {
                self.raw("\\n", .{});
                continue;
            }
            self.raw("{s}", .{tok.text});
        }
        self.raw("\"\n", .{});
    }

    fn doIndent(self: Self) void {
        var i: usize = 0;
        while (i < self.depth) : (i += 1) {
            self.raw("│ ", .{});
        }
    }
};

/// Scoped logger for module-specific logging.
/// Provides debug, info, warn, err methods with a module name prefix.
pub fn scopedLogger(comptime module_name: []const u8) ScopedLogger {
    return .{ .module_name = module_name };
}

/// A scoped logger that prefixes log messages with the module name.
pub const ScopedLogger = struct {
    module_name: []const u8,

    pub fn debug(self: ScopedLogger, comptime fmt: []const u8, args: anytype) void {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        stream.print("debug({s}): {s}\n", .{ self.module_name, msg }) catch {};
    }

    pub fn info(self: ScopedLogger, comptime fmt: []const u8, args: anytype) void {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        stream.print("info({s}): {s}\n", .{ self.module_name, msg }) catch {};
    }

    pub fn warn(self: ScopedLogger, comptime fmt: []const u8, args: anytype) void {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        stream.print("warning({s}): {s}\n", .{ self.module_name, msg }) catch {};
    }

    pub fn err(self: ScopedLogger, comptime fmt: []const u8, args: anytype) void {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        stream.print("error({s}): {s}\n", .{ self.module_name, msg }) catch {};
    }
};
