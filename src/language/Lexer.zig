//! A lexer for the Bussin language.

const std = @import("std");

const Config = @import("Config.zig");

const Lexer = @This();

/// The source text.
source: []const u8,

/// The current index in the source text.
index: usize = 0,

/// The start of the current token.
start: usize = 0,

/// The current token.
token: Token = .eof,

/// The Bussin configuration.
config: Config,

/// A token in the Bussin language.
pub const Token = union(enum) {
    // Other Types
    eof,
    unknown,
    unclosed_string,

    // Literal Types
    number_i32: i32,
    number_f64: f64,
    identifier: []const u8,
    string: []const u8,

    // Keywords
    let,
    @"const",
    @"fn",
    @"if",
    @"else",
    @"for",
    @"try",
    @"catch",
    true,
    false,
    null,

    // Operators
    @"+",
    @"-",
    @"*",
    @"/",
    @"%",
    @"=",
    @",",
    @":",
    @";",
    @".",
    @"(",
    @")",
    @"{",
    @"}",
    @"[",
    @"]",
    @">",
    @"<",
    @">=",
    @"<=",
    @"==",
    @"!=",
    @"!",
    @"&&",
    @"|",

    pub fn isError(tag: Tag) bool {
        return switch (tag) {
            .eof, .unknown, .unclosed_string => true,
            else => false,
        };
    }

    /// The tag for a token.
    pub const Tag = std.meta.Tag(Token);
};

/// Bussin keywords.
const bs_keywords = std.ComptimeStringMap(Token, .{
    .{ "let", .let },
    .{ "const", .@"const" },
    .{ "fn", .@"fn" },
    .{ "if", .@"if" },
    .{ "else", .@"else" },
    .{ "for", .@"for" },
    .{ "try", .@"try" },
    .{ "catch", .@"catch" },
    .{ "true", .true },
    .{ "false", .false },
    .{ "null", .null },
});

/// Bussin X keywords.
const bsx_keywords = std.ComptimeStringMap(Token, .{
    .{ "rn", .@";" },
    .{ "be", .@"=" },
    .{ "lit", .let },
    .{ "mf", .@"const" },
    .{ "sus", .@"if" },
    .{ "impostor", .@"else" },
    .{ "nah", .@"!=" },
    .{ "fr", .@"==" },
    .{ "btw", .@"&&" },
    .{ "carenot", .@"|" },
    .{ "bruh", .@"fn" },
    .{ "yall", .@"for" },
    .{ "smol", .@"<" },
    .{ "thicc", .@">" },
    .{ "fuck_around", .@"try" },
    .{ "find_out", .@"catch" },
    .{ "nocap", .true },
    .{ "cap", .false },
    .{ "fake", .null },
});

/// Initializes a lexer with the given source text.
pub fn init(source: []const u8, config: Config) Lexer {
    var lex = Lexer{ .source = source, .config = config };
    lex.next();
    return lex;
}

/// Returns the current byte in the source text or -1 if there are no more
/// bytes.
inline fn currentByte(lex: Lexer) i16 {
    return if (lex.index < lex.source.len) lex.source[lex.index] else -1;
}

/// Advances the lexer to the next token. Modifies the lexer in place.
pub fn next(lex: *Lexer) void {
    lex.start = lex.index;

    main: while (true) {
        switch (lex.currentByte()) {
            '(' => {
                lex.token = .@"(";
                lex.index += 1;
            },
            ')' => {
                lex.token = .@")";
                lex.index += 1;
            },
            '{' => {
                lex.token = .@"{";
                lex.index += 1;
            },
            '}' => {
                lex.token = .@"}";
                lex.index += 1;
            },
            '[' => {
                lex.token = .@"[";
                lex.index += 1;
            },
            ']' => {
                lex.token = .@"]";
                lex.index += 1;
            },
            ',' => {
                lex.token = .@",";
                lex.index += 1;
            },
            ':' => {
                lex.index += 1;
                lex.token = .@":";

                // It's ugly, but required for compatibility.
                if (std.mem.startsWith(u8, lex.source[lex.index..], " string")) {
                    lex.index += " string".len;
                    lex.start = lex.index;
                    continue :main;
                } else if (std.mem.startsWith(u8, lex.source[lex.index..], " number")) {
                    lex.index += " number".len;
                    lex.start = lex.index;
                    continue :main;
                } else if (std.mem.startsWith(u8, lex.source[lex.index..], " object")) {
                    lex.index += " object".len;
                    lex.start = lex.index;
                    continue :main;
                }
            },
            ';' => {
                lex.token = .@";";
                lex.index += 1;
            },
            '.' => {
                lex.index += 1;
                switch (lex.currentByte()) {
                    '0'...'9' => lex.eatNumberLiteral(true),
                    else => lex.token = .@".",
                }
            },
            '+' => {
                lex.token = .@"+";
                lex.index += 1;
            },
            '-' => {
                lex.index += 1;
                switch (lex.currentByte()) {
                    '0'...'9', '.' => lex.eatNumberLiteral(false),
                    else => lex.token = .@"-",
                }
            },
            '*' => {
                lex.token = .@"*";
                lex.index += 1;
            },
            '/' => {
                lex.token = .@"/";
                lex.index += 1;
            },
            '%' => {
                lex.token = .@"%";
                lex.index += 1;
            },
            '=' => {
                lex.index += 1;
                if (lex.currentByte() == '=') {
                    lex.token = .@"==";
                    lex.index += 1;
                } else {
                    lex.token = .@"=";
                }
            },
            '!' => {
                lex.index += 1;
                if (lex.currentByte() == '=') {
                    lex.token = .@"!=";
                    lex.index += 1;
                } else {
                    lex.token = .@"!";
                }
            },
            '&' => {
                lex.index += 1;
                if (lex.currentByte() == '&') {
                    lex.index += 1;
                    lex.token = .@"&&";
                } else {
                    lex.token = .unknown;
                }
            },
            '|' => {
                lex.index += 1;
                lex.token = .@"|";
            },
            '>' => {
                lex.index += 1;
                if (lex.currentByte() == '=') {
                    lex.index += 1;
                    lex.token = .@">=";
                } else {
                    lex.token = .@">";
                }
            },
            '<' => {
                lex.index += 1;
                if (lex.currentByte() == '=') {
                    lex.index += 1;
                    lex.token = .@"<=";
                } else {
                    lex.token = .@"<";
                }
            },
            ' ', '\t', '\n', '\r' => {
                lex.index += 1;
                lex.start = lex.index;
                continue :main;
            },
            '0'...'9' => lex.eatNumberLiteral(false),
            'a'...'z', 'A'...'Z', '_' => {
                while (true) {
                    lex.index += 1;

                    switch (lex.currentByte()) {
                        'a'...'z', 'A'...'Z', '0'...'9', '_' => {},
                        else => break,
                    }
                }

                const name = lex.source[lex.start..lex.index];
                lex.token = switch (lex.config.syntax) {
                    .bs => bs_keywords.get(name),
                    .bsx => bsx_keywords.get(name) orelse bs_keywords.get(name),
                } orelse .{ .identifier = name };
            },
            '"' => {
                while (true) {
                    lex.index += 1;

                    switch (lex.currentByte()) {
                        -1 => {
                            lex.token = .unclosed_string;
                            break :main;
                        },
                        '"' => {
                            lex.index += 1;
                            break;
                        },
                        else => {},
                    }
                }

                lex.token = .{ .string = lex.source[lex.start + 1 .. lex.index - 1] };
            },
            -1 => lex.token = .eof,
            else => lex.token = .unknown,
        }

        break :main;
    }
}

fn eatNumberLiteral(lex: *Lexer, init_seen_decimal: bool) void {
    var seen_decimal = init_seen_decimal;
    while (true) {
        switch (lex.currentByte()) {
            '0'...'9' => {},
            '.' => {
                if (seen_decimal) break;
                seen_decimal = true;
            },
            else => break,
        }
        lex.index += 1;
    }

    const buffer = lex.source[lex.start..lex.index];

    if (!seen_decimal) {
        if (std.fmt.parseInt(i32, buffer, 10) catch null) |value| {
            lex.token = .{ .number_i32 = value };
            return;
        }
    }

    lex.token = .{
        .number_f64 = std.fmt.parseFloat(f64, buffer) catch 0.0,
    };
}
