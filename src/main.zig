const std = @import("std");
const fs = std.fs;

const bytecode = @import("bytecode.zig");
const debug = @import("debug.zig");

const Value = @import("value.zig").Value;

const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

pub fn main() !void {
    var gpa = GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var alloc = gpa.allocator();

    var vm = VM.init(alloc);
    defer vm.deinit();

    var args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    if (args.len == 1) {
        try runFile(alloc, vm, "./test.gluon");
    } else {
        try runFile(alloc, vm, args[1]);
    }

    // var chunk = Chunk.init(alloc);
    // defer chunk.deinit();

    // const dummy_loc = bytecode.Loc{ .line = 42, .col = 42 };
    // chunk.write(bytecode.Op{ .op_constant = Value.fromNumber(42) }, dummy_loc);
    // chunk.write(bytecode.Op{ .op_constant = Value.fromNumber(1337) }, dummy_loc);
    // chunk.write(bytecode.Op{ .op_constant = Value.fromNumber(1234) }, dummy_loc);
    // chunk.write(bytecode.Op{ .op_sub = {} }, dummy_loc);
    // chunk.write(bytecode.Op{ .op_mul = {} }, dummy_loc);
    // chunk.write(bytecode.Op{ .op_neg = {} }, dummy_loc);
    // chunk.write(bytecode.Op{ .op_return = {} }, dummy_loc);
    // debug.disassemble(chunk, "test");

    // try vm.interpret(&chunk);
}

fn runFile(alloc: std.mem.Allocator, vm: *VM, filename: []const u8) !void {
    var f = try std.fs.cwd().openFile(filename, std.fs.File.OpenFlags{ .read = true });
    defer f.close();

    var buf = try f.readToEndAlloc(alloc, 1_000_000_000);
    defer alloc.free(buf);

    try vm.interpret(buf);
}

const print = std.debug.print;

const Chunk = bytecode.Chunk;

const VM = @import("vm.zig").VM;
