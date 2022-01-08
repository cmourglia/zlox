const std = @import("std");
const bytecode = @import("bytecode.zig");

const Value = @import("value.zig").Value;

const Str = []const u8;

pub fn disassemble(chunk: bytecode.Chunk, name: Str) void {
    print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.code.items.len) {
        offset = disassembleInst(chunk, offset);
    }
}

pub fn disassembleInst(chunk: bytecode.Chunk, offset: usize) usize {
    print("{d:0>4} ", .{offset});
    // print("({d:0>4}:{d:0>4}) ", .{ chunk.locs.items[offset].line, chunk.locs.items[offset].col });

    switch (@intToEnum(bytecode.Op, chunk.code.items[offset])) {
        .Constant => return constantInst("OP_CONSTANT", chunk, offset),
        .DefineGlobal => return constantInst("OP_DEFINE_GLOBAL", chunk, offset),
        .GetGlobal => return constantInst("OP_GET_GLOBAL", chunk, offset),
        .SetGlobal => return constantInst("OP_SET_GLOBAL", chunk, offset),
        .Return => return simpleInst("OP_RETURN", offset),
        .True => return simpleInst("OP_TRUE", offset),
        .False => return simpleInst("OP_FALSE", offset),
        .Nil => return simpleInst("OP_NIL", offset),
        .Add => return simpleInst("OP_ADD", offset),
        .Sub => return simpleInst("OP_SUB", offset),
        .Mul => return simpleInst("OP_MUL", offset),
        .Div => return simpleInst("OP_DIV", offset),
        .Neg => return simpleInst("OP_NEG", offset),
        .Not => return simpleInst("OP_NOT", offset),
        .And => return simpleInst("OP_AND", offset),
        .Or => return simpleInst("OP_OR", offset),
        .Xor => return simpleInst("OP_XOR", offset),
        .Equal => return simpleInst("OP_EQUAL", offset),
        .NotEqual => return simpleInst("OP_NOT_EQUAL", offset),
        .Greater => return simpleInst("OP_GREATER", offset),
        .GreaterEqual => return simpleInst("OP_GREATER_EQUAL", offset),
        .Less => return simpleInst("OP_LESS", offset),
        .LessEqual => return simpleInst("OP_LESS_EQUAL", offset),
        .Print => return simpleInst("OP_PRINT", offset),
        .Pop => return simpleInst("OP_POP", offset),
    }

    unreachable;
}

fn simpleInst(inst: Str, offset: usize) usize {
    print("{s}\n", .{inst});
    return offset + 1;
}

fn constantInst(inst: Str, chunk: bytecode.Chunk, offset: usize) usize {
    const value = chunk.getConstant(offset + 1);
    print("{s: <16} {}\n", .{ inst, value });

    return offset + 3;
}

const print = std.debug.print;
