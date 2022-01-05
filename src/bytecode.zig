// Copyright (c) 2022, Charly Mourglia <charly.mourglia@gmail.com>
// SPDX-License-Identifier: MIT

const std = @import("std");

const Str = []const u8;
const Bytecode = std.ArrayList(u8);
const Locations = std.ArrayList(Loc);

const Value = @import("value.zig").Value;
const Constants = std.ArrayList(Value);

pub const Op = enum {
    Return,
    Constant,
    True,
    False,
    Nil,
    Add,
    Sub,
    Mul,
    Div,
    Neg,
    Not,
    And,
    Or,
    Xor,
    Equal,
    NotEqual,
    Greater,
    GreaterEqual,
    Less,
    LessEqual,
    Print, // FIXME: Temporary
    Pop,
};

pub const Loc = struct {
    line: usize,
    col: usize,
};

const Words = packed struct {
    low: u8,
    high: u8,
};

const ConstantIndex = packed union {
    index: u16,
    words: Words,
};

pub const Chunk = struct {
    code: Bytecode,
    constants: Constants,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Chunk {
        return Chunk{
            .code = Bytecode.init(allocator),
            .constants = Constants.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.constants.deinit();
        self.code.deinit();
    }

    fn addConstant(self: *Self, value: Value) ConstantIndex {
        const id = @intCast(u16, self.constants.items.len);
        self.constants.append(value) catch unreachable;
        return ConstantIndex{ .index = id };
    }

    pub fn pushConstant(self: *Self, value: Value) void {
        const id = self.addConstant(value);
        self.code.append(id.words.low) catch unreachable;
        self.code.append(id.words.high) catch unreachable;
    }

    pub fn push(self: *Self, op: Op) void {
        const op_index = @enumToInt(op);
        self.code.append(op_index) catch unreachable;
    }

    pub fn getConstant(self: Self, ip: usize) Value {
        const index = ConstantIndex{
            .words = Words{
                .low = self.code.items[ip],
                .high = self.code.items[ip + 1],
            },
        };

        return self.constants.items[@intCast(usize, index.index)];
    }
};
