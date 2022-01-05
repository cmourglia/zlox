// Copyright (c) 2022, Charly Mourglia <charly.mourglia@gmail.com>
// SPDX-License-Identifier: MIT

const std = @import("std");
const bytecode = @import("bytecode.zig");
const gc = @import("gc.zig");

const InterpreterError = @import("vm.zig").InterpreterError;
const Scanner = @import("scanner.zig").Scanner;
const Token = @import("scanner.zig").Token;
const TokenType = @import("scanner.zig").TokenType;
const Value = @import("value.zig").Value;

const Precedence = enum(usize) {
    None,
    Assignment,
    Or,
    Xor,
    And,
    Equality,
    Comparison,
    Term,
    Factor,
    Unary,
    Call,
    Primary,
};

const ParseFn = fn (parser: *Parser) void;

const ParseRule = struct {
    prefix: ?ParseFn,
    infix: ?ParseFn,
    precedence: Precedence,

    fn init(prefix: ?ParseFn, infix: ?ParseFn, precedence: Precedence) ParseRule {
        return ParseRule{
            .prefix = prefix,
            .infix = infix,
            .precedence = precedence,
        };
    }
};

const parse_rules = t: {
    comptime var prec = std.enums.EnumArray(TokenType, ParseRule).initUndefined();

    prec.set(.OpenParen, ParseRule.init(Parser.compileGrouping, null, .None));
    prec.set(.CloseParen, ParseRule.init(null, null, .None));
    prec.set(.OpenBrace, ParseRule.init(null, null, .None));
    prec.set(.CloseBrace, ParseRule.init(null, null, .None));
    prec.set(.OpenBracket, ParseRule.init(null, null, .None));
    prec.set(.CloseBracket, ParseRule.init(null, null, .None));
    prec.set(.Comma, ParseRule.init(null, null, .None));
    prec.set(.Dot, ParseRule.init(null, null, .None));
    prec.set(.Semicolon, ParseRule.init(null, null, .None));
    prec.set(.Equal, ParseRule.init(null, null, .None));

    prec.set(.Not, ParseRule.init(Parser.compileUnary, null, .None));

    prec.set(.Minus, ParseRule.init(Parser.compileUnary, Parser.compileBinary, .Term));
    prec.set(.Plus, ParseRule.init(null, Parser.compileBinary, .Term));
    prec.set(.Slash, ParseRule.init(null, Parser.compileBinary, .Factor));
    prec.set(.Star, ParseRule.init(null, Parser.compileBinary, .Factor));

    prec.set(.MinusEqual, ParseRule.init(null, null, .None));
    prec.set(.PlusEqual, ParseRule.init(null, null, .None));
    prec.set(.SlashEqual, ParseRule.init(null, null, .None));
    prec.set(.StarEqual, ParseRule.init(null, null, .None));

    prec.set(.EqualEqual, ParseRule.init(null, Parser.compileBinary, .Equality));
    prec.set(.BangEqual, ParseRule.init(null, Parser.compileBinary, .Equality));
    prec.set(.Less, ParseRule.init(null, Parser.compileBinary, .Comparison));
    prec.set(.LessEqual, ParseRule.init(null, Parser.compileBinary, .Comparison));
    prec.set(.Greater, ParseRule.init(null, Parser.compileBinary, .Comparison));
    prec.set(.GreaterEqual, ParseRule.init(null, Parser.compileBinary, .Comparison));

    prec.set(.Number, ParseRule.init(Parser.compileNumber, null, .None));
    prec.set(.String, ParseRule.init(Parser.compileString, null, .None));

    prec.set(.Nil, ParseRule.init(Parser.compileLiteral, null, .None));
    prec.set(.False, ParseRule.init(Parser.compileLiteral, null, .None));
    prec.set(.True, ParseRule.init(Parser.compileLiteral, null, .None));

    prec.set(.Or, ParseRule.init(null, Parser.compileBinary, .Or));
    prec.set(.And, ParseRule.init(null, Parser.compileBinary, .And));
    prec.set(.Xor, ParseRule.init(null, Parser.compileBinary, .Xor));

    prec.set(.Identifier, ParseRule.init(null, null, .None));
    prec.set(.Class, ParseRule.init(null, null, .None));
    prec.set(.Else, ParseRule.init(null, null, .None));
    prec.set(.For, ParseRule.init(null, null, .None));
    prec.set(.Fn, ParseRule.init(null, null, .None));
    prec.set(.If, ParseRule.init(null, null, .None));
    prec.set(.Let, ParseRule.init(null, null, .None));
    prec.set(.Return, ParseRule.init(null, null, .None));
    prec.set(.Super, ParseRule.init(null, null, .None));
    prec.set(.Switch, ParseRule.init(null, null, .None));
    prec.set(.This, ParseRule.init(null, null, .None));
    prec.set(.While, ParseRule.init(null, null, .None));
    prec.set(.Print, ParseRule.init(null, null, .None));
    prec.set(.Error, ParseRule.init(null, null, .None));
    prec.set(.EOF, ParseRule.init(null, null, .None));

    break :t prec;
};

// TODO: For now, we are doing single pass compilation.
// At some point, we will need to optimize a bit of stuff and so on,
// so we might need an AST.

// TODO: At some point, we will really need true error handling,
// this is very crappy right now
pub fn compile(source: []const u8, chunk: *bytecode.Chunk, heap: *gc.Heap) bool {
    var scanner = Scanner.init(source);
    var parser = Parser.init(&scanner, chunk, heap);

    return parser.run();
}

const Parser = struct {
    current: Token = Token{},
    previous: Token = undefined,
    hadError: bool = false,
    panicMode: bool = false,

    scanner: *Scanner,
    chunk: *bytecode.Chunk,
    heap: *gc.Heap,

    const Self = @This();

    fn init(scanner: *Scanner, chunk: *bytecode.Chunk, heap: *gc.Heap) Self {
        return Parser{
            .scanner = scanner,
            .chunk = chunk,
            .heap = heap,
        };
    }

    fn run(self: *Self) bool {
        self.advance();

        while (!self.match(.EOF)) {
            self.compileDeclaration();
        }

        self.endCompiler();
        return !self.hadError;
    }

    fn endCompiler(self: *Self) void {
        self.chunk.push(.Return);
    }

    fn parsePrecedence(self: *Self, precedence: Precedence) void {
        self.advance();
        const rule = parse_rules.get(self.previous.token_type);
        const prefix_rule = rule.prefix;

        if (prefix_rule == null) {
            self.errorAtPrevious("Expect an expression.");
            return;
        }

        prefix_rule.?(self);

        const prec_value = @enumToInt(precedence);
        while (prec_value <= @enumToInt(parse_rules.get(self.current.token_type).precedence)) {
            self.advance();
            const infix_rule = parse_rules.get(self.previous.token_type).infix;

            if (infix_rule != null) {
                infix_rule.?(self);
            }
        }
    }

    fn compileDeclaration(self: *Self) void {
        if (self.match(.Let)) {
            self.compileVarDecl();
        } else {
            self.compileStatement();
        }

        if (self.panicMode) {
            self.synchronize();
        }
    }

    fn compileVarDecl(self: *Self) void {
        _ = self;
    }

    fn compileStatement(self: *Self) void {
        if (self.match(.Print)) {
            self.compilePrintStatement();
        } else {
            self.compileExpressionStatement();
        }
    }

    fn compilePrintStatement(self: *Self) void {
        self.consume(.OpenParen, "`print()` is a function, please call it like other functions");
        self.compileExpression();
        self.consume(.CloseParen, "`)` expected");
        self.consume(.Semicolon, "Expected a `;` after a function call");

        self.emitOp(.Print);
    }

    fn compileExpressionStatement(self: *Self) void {
        self.compileExpression();
        self.consume(.Semicolon, "Expect a `;` after an expression");

        self.emitOp(.Pop);
    }

    fn compileExpression(self: *Self) void {
        self.parsePrecedence(.Assignment);
    }

    fn compileNumber(self: *Self) void {
        const value = std.fmt.parseFloat(f64, self.previous.lexeme) catch std.math.nan_f64;
        self.emitConstant(Value.fromNumber(value));
    }

    fn compileString(self: *Self) void {
        const source_str = self.previous.lexeme;
        const str = self.heap.makeString();

        str.concat(.{source_str}) catch unreachable;

        self.emitConstant(Value.fromString(str));
    }

    fn compileLiteral(self: *Self) void {
        switch (self.previous.token_type) {
            .True => self.chunk.push(.True),
            .False => self.chunk.push(.False),
            .Nil => self.chunk.push(.Nil),
            else => {},
        }
    }

    fn compileGrouping(self: *Self) void {
        self.compileExpression();
        self.consume(TokenType.CloseParen, "Expect `)` after an expression.");
    }

    fn compileUnary(self: *Self) void {
        const operator_type = self.previous.token_type;

        self.parsePrecedence(.Unary);

        switch (operator_type) {
            .Minus => self.emitOp(.Neg),
            .Not => self.emitOp(.Not),
            else => {},
        }
    }

    fn compileBinary(self: *Self) void {
        const operator_type = self.previous.token_type;
        var rule = parse_rules.get(operator_type);
        self.parsePrecedence(@intToEnum(Precedence, @enumToInt(rule.precedence) + 1));

        switch (operator_type) {
            .Plus => self.emitOp(.Add),
            .Minus => self.emitOp(.Sub),
            .Star => self.emitOp(.Mul),
            .Slash => self.emitOp(.Div),

            .And => self.emitOp(.And),
            .Or => self.emitOp(.Or),
            .Xor => self.emitOp(.Xor),

            .EqualEqual => self.emitOp(.Equal),
            .BangEqual => self.emitOp(.NotEqual),
            .Greater => self.emitOp(.Greater),
            .GreaterEqual => self.emitOp(.GreaterEqual),
            .Less => self.emitOp(.Less),
            .LessEqual => self.emitOp(.LessEqual),

            else => {},
        }
    }

    fn emitOp(self: *Self, op: bytecode.Op) void {
        self.chunk.push(op);
    }

    fn emitConstant(self: *Self, value: Value) void {
        self.chunk.push(.Constant);
        self.chunk.pushConstant(value);
    }

    fn advance(self: *Self) void {
        self.previous = self.current;

        while (true) {
            self.current = self.scanner.next();
            switch (self.current.token_type) {
                .Error => {
                    self.errorAtCurrent(self.current.lexeme);
                    continue;
                },
                else => {},
            }
            break;
        }
    }

    fn consume(self: *Self, token_type: TokenType, msg: []const u8) void {
        if (self.current.token_type == token_type) {
            self.advance();
        } else {
            self.errorAtCurrent(msg);
        }
    }

    fn check(self: *Self, token_type: TokenType) bool {
        return self.current.token_type == token_type;
    }

    fn match(self: *Self, token_type: TokenType) bool {
        if (!self.check(token_type)) return false;
        self.advance();
        return true;
    }

    fn errorAt(self: *Self, token: Token, msg: []const u8) void {
        if (!self.panicMode) {
            switch (token.token_type) {
                .Error => {
                    std.debug.print("Syntax error (line {}): {s}.\n", .{ token.location.line, msg });
                },
                else => {
                    std.debug.print("Compile error (line {}): {s}.\n", .{ token.location.line, msg });
                },
            }

            self.hadError = true;
            self.panicMode = true;
        }
    }

    fn errorAtCurrent(self: *Self, msg: []const u8) void {
        self.errorAt(self.current, msg);
    }

    fn errorAtPrevious(self: *Self, msg: []const u8) void {
        self.errorAt(self.previous, msg);
    }

    fn synchronize(self: *Self) void {
        self.panicMode = false;

        while (self.current.token_type != .EOF) {
            if (self.previous.token_type == .Semicolon) return;
            switch (self.current.token_type) {
                .Class, .Fn, .Let, .For, .If, .While, .Print, .Return => return,
                else => {},
            }

            self.advance();
        }
    }
};
