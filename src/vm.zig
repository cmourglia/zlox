// Copyright (c) 2022, Charly Mourglia <charly.mourglia@gmail.com>
// SPDX-License-Identifier: MIT

const std = @import("std");

const bytecode = @import("bytecode.zig");
const compiler = @import("compiler.zig");
const debug = @import("debug.zig");
const gc = @import("gc.zig");

const Value = @import("value.zig").Value;
const Heap = gc.Heap;

const DEBUG_TRACE_EXECUTION = true;

pub const InterpreterError = error{
    ScanError,
    CompileError,
    RuntimeError,
    CastError,
    CannotCompareValuesError,
    NonsensicalComparisonError,
    NonsensicalOperationError,
    StackOverflowError,
    StackUnderflowError,
    InvalidOperationError,
};

var the_vm: VM = undefined;

pub fn vm() *VM {
    return &the_vm;
}

pub const VM = struct {
    chunk: *bytecode.Chunk = undefined,
    ip: usize = 0,
    allocator: std.mem.Allocator,
    // FIXME: Not sure about wether we should use a stack or
    //        heap allocated array here.
    stack: std.ArrayList(Value),
    heap: Heap,

    // Keep this list of roots to avoid allocating / deallocating a list on every garbage collection
    root_list: std.ArrayList(*const Value),
    running: bool = false,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) *Self {
        the_vm = VM{
            .allocator = allocator,
            .stack = std.ArrayList(Value).init(allocator),
            .heap = Heap.init(allocator),
            .root_list = std.ArrayList(*const Value).init(allocator),
        };
        return vm();
    }

    pub fn deinit(self: *Self) void {
        self.root_list.deinit();
        self.heap.deinit();
        self.stack.deinit();
    }

    pub fn interpret(self: *Self, buf: []const u8) InterpreterError!void {
        var chunk = bytecode.Chunk.init(self.allocator);
        defer chunk.deinit();

        if (!compiler.compile(buf, &chunk, &self.heap)) {
            return InterpreterError.CompileError;
        }

        self.chunk = &chunk;
        self.ip = 0;

        try self.run();
    }

    fn run(self: *Self) InterpreterError!void {
        self.running = true;
        defer self.running = false;

        while (true) : (self.ip += 1) {
            var inst = @intToEnum(bytecode.Op, self.chunk.code.items[self.ip]);

            if (DEBUG_TRACE_EXECUTION) {
                _ = debug.disassembleInst(self.chunk.*, self.ip);
            }

            switch (inst) {
                .Return => {
                    break;
                },
                .Constant => {
                    // TODO: Get value
                    const value = self.chunk.getConstant(self.ip + 1);
                    self.ip += 2;
                    self.push(value);
                },
                .True => self.push(Value.fromBoolean(true)),
                .False => self.push(Value.fromBoolean(false)),
                .Nil => self.push(Value.fromNil()),
                .Add => try self.binaryOp(opAdd),
                .Sub => try self.binaryOp(opSub),
                .Mul => try self.binaryOp(opMul),
                .Div => try self.binaryOp(opDiv),
                .And => try self.binaryOp(opAnd),
                .Or => try self.binaryOp(opOr),
                .Xor => try self.binaryOp(opXor),
                .Equal => try self.binaryOp(opEq),
                .NotEqual => try self.binaryOp(opNeq),
                .Greater => try self.binaryOp(opGt),
                .GreaterEqual => try self.binaryOp(opGEq),
                .Less => try self.binaryOp(opLt),
                .LessEqual => try self.binaryOp(opLEq),
                .Neg => {
                    const value = try (self.pop()).asNumber();
                    self.push(Value.fromNumber(-value));
                },
                .Not => {
                    const value = try (self.pop()).asBoolean();
                    self.push(Value.fromBoolean(!value));
                },
                .Print => {
                    const value = self.pop();
                    std.debug.print("{}\n", .{value});
                },
                .Pop => _ = self.pop(),
            }
        }
    }

    fn pushReplace(self: *Self, value: Value) void {
        _ = self.pop();
        _ = self.pop();
        self.push(value);
    }

    fn push(self: *Self, value: Value) void {
        self.stack.append(value) catch unreachable;
    }

    fn pop(self: *Self) Value {
        var result = self.stack.popOrNull() orelse unreachable;
        return result;
    }

    fn peek(self: Self, distance: usize) Value {
        return self.stack.items[self.stack.items.len - 1 - distance];
    }

    pub fn gatherRoots(self: *Self) []*const Value {
        self.root_list.clearRetainingCapacity();

        // Chunk constants are roots
        for (self.chunk.constants.items) |*v| {
            self.root_list.append(v) catch unreachable;
        }

        // Stack data are roots
        for (self.stack.items) |*v| {
            self.root_list.append(v) catch unreachable;
        }
        return self.root_list.items;
    }

    fn binaryOp(self: *Self, op: BinaryFn) InterpreterError!void {
        self.pushReplace(try op(self.peek(1), self.peek(0)));
    }
};

const BinaryFn = fn (lhs: Value, rhs: Value) InterpreterError!Value;

fn opAdd(lhs: Value, rhs: Value) InterpreterError!Value {
    if (!Value.sharesType(lhs, rhs)) {
        return InterpreterError.CannotCompareValuesError;
    }

    switch (lhs) {
        .number => {
            const n1 = lhs.asNumber() catch unreachable;
            const n2 = rhs.asNumber() catch unreachable;
            return Value.fromNumber(n1 + n2);
        },
        .string => {
            const s1 = lhs.asString() catch unreachable;
            const s2 = rhs.asString() catch unreachable;

            const str = vm().heap.makeString();
            str.concat(.{ s1.str(), s2.str() }) catch return InterpreterError.RuntimeError;

            return Value.fromString(str);
        },
        else => return InterpreterError.NonsensicalOperationError,
    }
}

fn opSub(lhs: Value, rhs: Value) InterpreterError!Value {
    if (!Value.sharesType(lhs, rhs)) {
        return InterpreterError.CannotCompareValuesError;
    }

    switch (lhs) {
        .number => {
            const n1 = lhs.asNumber() catch unreachable;
            const n2 = rhs.asNumber() catch unreachable;
            return Value.fromNumber(n1 - n2);
        },
        else => return InterpreterError.NonsensicalOperationError,
    }
}

fn opMul(lhs: Value, rhs: Value) InterpreterError!Value {
    if (lhs.isString() and rhs.isNumber()) {
        const s = lhs.asString() catch unreachable;
        const n = @floatToInt(usize, rhs.asNumber() catch unreachable);

        const str = vm().heap.makeString();

        str.concatNTimes(s.str(), n) catch return InterpreterError.RuntimeError;

        return Value.fromString(str);
    } else {
        if (!Value.sharesType(lhs, rhs)) {
            return InterpreterError.CannotCompareValuesError;
        }

        switch (lhs) {
            .number => {
                const n1 = lhs.asNumber() catch unreachable;
                const n2 = rhs.asNumber() catch unreachable;
                return Value.fromNumber(n1 * n2);
            },
            else => return InterpreterError.NonsensicalOperationError,
        }
    }
}

fn opDiv(lhs: Value, rhs: Value) InterpreterError!Value {
    if (!Value.sharesType(lhs, rhs)) {
        return InterpreterError.CannotCompareValuesError;
    }

    switch (lhs) {
        .number => {
            const n1 = lhs.asNumber() catch unreachable;
            const n2 = rhs.asNumber() catch unreachable;
            return Value.fromNumber(n1 / n2);
        },
        else => return InterpreterError.NonsensicalOperationError,
    }
}

fn opAnd(lhs: Value, rhs: Value) InterpreterError!Value {
    var lhs_bool = try lhs.asBoolean();
    var rhs_bool = try rhs.asBoolean();

    return Value.fromBoolean(lhs_bool and rhs_bool);
}

fn opOr(lhs: Value, rhs: Value) InterpreterError!Value {
    var lhs_bool = try lhs.asBoolean();
    var rhs_bool = try rhs.asBoolean();

    return Value.fromBoolean(lhs_bool or rhs_bool);
}

fn opXor(lhs: Value, rhs: Value) InterpreterError!Value {
    var lhs_bool = try lhs.asBoolean();
    var rhs_bool = try rhs.asBoolean();

    return Value.fromBoolean((lhs_bool and !rhs_bool) or (rhs_bool and !lhs_bool));
}

fn opEq(lhs: Value, rhs: Value) InterpreterError!Value {
    return Value.fromBoolean(try Value.equals(lhs, rhs));
}

fn opNeq(lhs: Value, rhs: Value) InterpreterError!Value {
    return Value.fromBoolean(!try Value.equals(lhs, rhs));
}

fn opGt(lhs: Value, rhs: Value) InterpreterError!Value {
    return Value.fromBoolean(try Value.greaterThan(lhs, rhs));
}

fn opGEq(lhs: Value, rhs: Value) InterpreterError!Value {
    return Value.fromBoolean(try lhs.greaterThanOrEqual(rhs));
}

fn opLt(lhs: Value, rhs: Value) InterpreterError!Value {
    return Value.fromBoolean(try lhs.lessThan(rhs));
}

fn opLEq(lhs: Value, rhs: Value) InterpreterError!Value {
    return Value.fromBoolean(try lhs.lessThanOrEqual(rhs));
}
