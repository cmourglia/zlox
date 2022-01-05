// Copyright (c) 2022, Charly Mourglia <charly.mourglia@gmail.com>
// SPDX-License-Identifier: MIT

const std = @import("std");

pub const TokenType = enum {
    // Single char tokens
    OpenParen,
    CloseParen,
    OpenBrace,
    CloseBrace,
    OpenBracket,
    CloseBracket,
    Comma,
    Dot,
    Semicolon,

    // One or two char tokens
    Equal,
    EqualEqual,
    BangEqual,
    Less,
    LessEqual,
    Greater,
    GreaterEqual,
    Minus,
    MinusEqual,
    Plus,
    PlusEqual,
    Slash,
    SlashEqual,
    Star,
    StarEqual,

    // Literals
    Identifier,
    String,
    Number,

    // Keywords
    And,
    Class,
    Else,
    False,
    For,
    Fn,
    If,
    Let,
    Nil,
    Not,
    Or,
    Return,
    Super,
    Switch,
    This,
    True,
    While,
    Xor,

    // Temp
    Print,

    // Special cases
    // TODO: At some point, we might want to use zig's error type again.
    // But for now, since it does not allow adding info to the errors,
    // we will need to deal with this special "error token".
    Error,
    EOF,
};

const Location = struct {
    line: u32 = 0,
};

pub const Token = struct {
    token_type: TokenType = .Error,
    lexeme: []const u8 = "",
    location: Location = Location{},
};

const keywords_map = std.ComptimeStringMap(TokenType, .{
    .{ "and", .And },
    .{ "class", .Class },
    .{ "else", .Else },
    .{ "false", .False },
    .{ "for", .For },
    .{ "fn", .Fn },
    .{ "if", .If },
    .{ "let", .Let },
    .{ "nil", .Nil },
    .{ "not", .Not },
    .{ "or", .Or },
    .{ "return", .Return },
    .{ "super", .Super },
    .{ "switch", .Switch },
    .{ "this", .This },
    .{ "true", .True },
    .{ "while", .While },
    .{ "xor", .Xor },
    .{ "print", .Print },
});

fn isDigit(c: u8) bool {
    return (c >= '0' and c <= '9');
}

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isAlphanum(c: u8) bool {
    return isAlpha(c) or isDigit(c);
}

pub const Scanner = struct {
    buffer: []const u8,
    current: usize = 0,
    start: usize = 0,
    line: u32 = 1,

    const Self = @This();

    pub fn init(source: []const u8) Self {
        return Scanner{ .buffer = source };
    }

    pub fn next(self: *Self) Token {
        self.skipIgnored();

        self.start = self.current;
        if (self.start == self.buffer.len) {
            return self.makeToken(TokenType.EOF);
        }

        var c = self.advance();

        switch (c) {
            // Single char tokens
            '(' => return self.makeToken(TokenType.OpenParen),
            ')' => return self.makeToken(TokenType.CloseParen),
            '{' => return self.makeToken(TokenType.OpenBrace),
            '}' => return self.makeToken(TokenType.CloseBrace),
            '[' => return self.makeToken(TokenType.OpenBracket),
            ']' => return self.makeToken(TokenType.CloseBracket),
            ';' => return self.makeToken(TokenType.Semicolon),
            ',' => return self.makeToken(TokenType.Comma),
            '.' => return self.makeToken(TokenType.Dot),

            // One or two char tokens
            '=' => if (self.match('=')) return self.makeToken(TokenType.EqualEqual) else return self.makeToken(TokenType.Equal),
            '<' => if (self.match('=')) return self.makeToken(TokenType.LessEqual) else return self.makeToken(TokenType.Less),
            '>' => if (self.match('=')) return self.makeToken(TokenType.GreaterEqual) else return self.makeToken(TokenType.Greater),
            '+' => if (self.match('=')) return self.makeToken(TokenType.PlusEqual) else return self.makeToken(TokenType.Plus),
            '-' => if (self.match('=')) return self.makeToken(TokenType.MinusEqual) else return self.makeToken(TokenType.Minus),
            '*' => if (self.match('=')) return self.makeToken(TokenType.StarEqual) else return self.makeToken(TokenType.Star),
            '/' => if (self.match('=')) return self.makeToken(TokenType.SlashEqual) else return self.makeToken(TokenType.Slash),
            '!' => if (self.match('=')) return self.makeToken(TokenType.BangEqual) else return self.errorToken("`!` is not a valid token. Maybe you were meaning `not` ?"),

            // String literals
            '"' => return self.string(),

            else => {
                if (isDigit(c)) return self.number();
                if (isAlpha(c)) return self.identifier();
            },
        }

        return self.errorToken("Unexpected character.");
    }

    /// Skip whitespaces and comments.
    fn skipIgnored(self: *Self) void {
        while (true) {
            var c = self.peek();
            switch (c) {
                ' ', '\t', '\r' => _ = self.advance(),
                '\n' => {
                    self.line += 1;
                    _ = self.advance();
                },
                '/' => {
                    if (self.peekNext() == '/') {
                        // This is a comment
                        while (!self.done() and self.peek() != '\n') _ = self.advance();
                    } else {
                        return;
                    }
                },
                else => return,
            }
        }
    }

    fn advance(self: *Self) u8 {
        self.current += 1;
        return self.buffer[self.current - 1];
    }

    fn peek(self: *Self) u8 {
        if (self.current == self.buffer.len) {
            return 0;
        }

        return self.buffer[self.current];
    }

    fn done(self: Self) bool {
        return self.current >= self.buffer.len;
    }

    fn peekNext(self: *Self) u8 {
        if (self.current + 1 == self.buffer.len) {
            return 0;
        }

        return self.buffer[self.current + 1];
    }

    fn match(self: *Self, char: u8) bool {
        if (self.current == self.buffer.len) return false;
        if (self.buffer[self.current] != char) return false;

        self.current += 1;
        return true;
    }

    fn makeToken(self: *Self, token_type: TokenType) Token {
        return Token{
            .token_type = token_type,
            .lexeme = self.buffer[self.start..self.current],
        };
    }

    fn errorToken(self: *Self, message: []const u8) Token {
        _ = self;
        return Token{
            .token_type = .Error,
            .lexeme = message,
            .location = Location{ .line = 42 },
        };
    }

    fn string(self: *Self) Token {
        while (true) {
            var c = self.peek();
            if (c == 0) {
                return self.errorToken("Unexpected end of file.");
            }

            if (c == '\n') {
                self.line += 1;
            }

            if (c == '"') {
                // Did we escape a " ?
                if (self.buffer[self.current - 1] != '\\') {
                    // Nah
                    self.start += 1;
                    const token = self.makeToken(TokenType.String);
                    _ = self.advance();
                    return token;
                }
            }

            _ = self.advance();
        }

        return self.errorToken("Unexpected end of file.");
    }

    fn number(self: *Self) Token {
        while (isDigit(self.peek())) {
            _ = self.advance();
        }
        if ((self.peek()) == '.') {
            if (!isDigit(self.peekNext())) {
                return self.errorToken("A number cannot end with a `.` character.");
            }
            _ = self.advance();
        }
        while (isDigit(self.peek())) {
            _ = self.advance();
        }

        return self.makeToken(TokenType.Number);
    }

    fn identifier(self: *Self) Token {
        while (isAlphanum(self.peek())) _ = self.advance();

        // TODO: Check a trie dumb implementation (aka clox)
        const identifier_str = self.buffer[self.start..self.current];
        const keyword = keywords_map.get(identifier_str) orelse return self.makeToken(TokenType.Identifier);

        return self.makeToken(keyword);
    }
};
