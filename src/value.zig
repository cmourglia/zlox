// Copyright (c) 2022, Charly Mourglia <charly.mourglia@gmail.com>
// SPDX-License-Identifier: MIT

const std = @import("std");
const gc = @import("gc.zig");

const InterpreterError = @import("vm.zig").InterpreterError;
const Heap = gc.Heap;
const HeapId = gc.HeapId;

const vm = @import("vm.zig").vm;
const range = @import("utils.zig").range;

var format_level: u8 = 0;

pub const Object = struct {
    id: HeapId,
    members: std.StringHashMap(Value),

    const Self = @This();

    pub fn init(id: HeapId, allocator: std.mem.Allocator) Self {
        return Self{ .id = id, .members = std.StringHashMap(Value).init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.members.deinit();
    }

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;

        format_level += 1;
        var it = self.members.iterator();
        var first = true;
        try std.fmt.format(writer, "{{", .{});
        while (true) {
            var entry = it.next();
            if (entry == null) break;

            if (!first) {
                try std.fmt.format(writer, ",", .{});
            } else {
                first = false;
            }

            try std.fmt.format(writer, "\n", .{});
            try printIndent(writer);
            try std.fmt.format(writer, "{s}: {}", .{ entry.?.key_ptr.*, entry.?.value_ptr.* });
        }
        format_level -= 1;

        if (self.members.count() != 0) {
            try printIndent(writer);
        }
        try std.fmt.format(writer, "}}", .{});
    }
};

fn printIndent(writer: anytype) !void {
    var lvl: u8 = 0;
    while (lvl < format_level) : (lvl += 1) {
        try std.fmt.format(writer, "  ", .{});
    }
}

// TODO: Add a string pool
pub const String = struct {
    id: HeapId,
    string: std.ArrayList(u8),

    const Self = @This();

    pub fn init(id: HeapId, allocator: std.mem.Allocator) Self {
        return Self{ .id = id, .string = std.ArrayList(u8).init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.string.deinit();
    }

    pub fn str(self: Self) []u8 {
        return self.string.items;
    }

    pub fn concat(self: *Self, others: anytype) !void {
        var total_size: usize = self.string.items.len;

        comptime var i: usize = 0;
        inline while (i < others.len) : (i += 1) {
            total_size += others[i].len;
        }
        try self.string.ensureTotalCapacity(total_size);

        i = 0;
        inline while (i < others.len) : (i += 1) {
            try self.string.appendSlice(others[i]);
        }
    }

    pub fn concatNTimes(self: *Self, other: []const u8, n: usize) !void {
        try self.string.ensureTotalCapacity(self.string.items.len + other.len);

        for (range(n)) |_| {
            try self.string.appendSlice(other);
        }
    }

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        return std.fmt.format(writer, "\"{s}\"", .{self.string.items});
    }
};

pub const Value = union(enum) {
    number: f64,
    boolean: bool,
    nil: void,
    string: *String,
    object: *Object,

    pub fn fromNumber(n: f64) Value {
        return Value{ .number = n };
    }

    pub fn fromBoolean(b: bool) Value {
        return Value{ .boolean = b };
    }

    pub fn fromNil() Value {
        return Value{ .nil = {} };
    }

    pub fn fromString(string: *String) Value {
        return Value{ .string = string };
    }

    pub fn asNumber(self: Value) InterpreterError!f64 {
        switch (self) {
            .number => |v| return v,
            else => return InterpreterError.CastError,
        }
    }

    pub fn asBoolean(self: Value) InterpreterError!bool {
        switch (self) {
            .boolean => |v| return v,
            else => return InterpreterError.CastError,
        }
    }

    pub fn asNil(self: Value) InterpreterError!void {
        switch (self) {
            .nil => {},
            else => return InterpreterError.CastError,
        }
    }

    pub fn asString(self: Value) InterpreterError!*String {
        switch (self) {
            .string => |s| return s,
            else => return InterpreterError.CastError,
        }
    }

    pub fn asObject(self: Value) InterpreterError!*Object {
        switch (self) {
            .object => |o| return o,
            else => return InterpreterError.CastError,
        }
    }

    pub fn isNumber(self: Value) bool {
        switch (self) {
            .number => return true,
            else => return false,
        }
    }

    pub fn isBoolean(self: Value) bool {
        switch (self) {
            .boolean => return true,
            else => return false,
        }
    }

    pub fn isNil(self: Value) bool {
        switch (self) {
            .nil => return true,
            else => return false,
        }
    }

    pub fn isString(self: Value) bool {
        switch (self) {
            .string => return true,
            else => return false,
        }
    }

    pub fn isObject(self: Value) bool {
        switch (self) {
            .object => return true,
            else => return false,
        }
    }

    pub fn sharesType(lhs: Value, rhs: Value) bool {
        return @enumToInt(lhs) == @enumToInt(rhs);
    }

    pub fn equals(lhs: Value, rhs: Value) InterpreterError!bool {
        if (!sharesType(lhs, rhs)) {
            return InterpreterError.CannotCompareValuesError;
        }

        switch (lhs) {
            // TODO: Remove nil
            .nil => return true,
            .boolean => {
                const b1 = @field(lhs, "boolean");
                const b2 = @field(rhs, "boolean");
                return b1 == b2;
            },
            .number => {
                const n1 = @field(lhs, "number");
                const n2 = @field(rhs, "number");
                return n1 == n2;
            },
            .string => {
                const s1 = @field(lhs, "string");
                const s2 = @field(rhs, "string");

                return std.mem.eql(u8, s1.str(), s2.str());
            },
            .object => {
                const id1 = @field(lhs, "object");
                const id2 = @field(rhs, "object");
                // Should we be smarter than a pointer comparison here ?
                return id1 == id2;
            },
        }

        unreachable;
    }

    pub fn greaterThan(lhs: Value, rhs: Value) InterpreterError!bool {
        if (!sharesType(lhs, rhs)) {
            return InterpreterError.CannotCompareValuesError;
        }

        switch (lhs) {
            // TODO: Remove nil
            .number => {
                const n1 = @field(lhs, "number");
                const n2 = @field(rhs, "number");
                return n1 > n2;
            },
            .string => {
                const s1 = @field(lhs, "string");
                const s2 = @field(rhs, "string");

                const order = std.mem.order(u8, s1.str(), s2.str());
                return order == .gt;
            },
            else => return InterpreterError.NonsensicalComparisonError,
        }

        unreachable;
    }

    pub fn greaterThanOrEqual(lhs: Value, rhs: Value) InterpreterError!bool {
        if (!sharesType(lhs, rhs)) {
            return InterpreterError.CannotCompareValuesError;
        }

        switch (lhs) {
            // TODO: Remove nil
            .number => {
                const n1 = @field(lhs, "number");
                const n2 = @field(rhs, "number");
                return n1 == n2;
            },
            .string => {
                const s1 = @field(lhs, "string");
                const s2 = @field(rhs, "string");

                const order = std.mem.order(u8, s1.str(), s2.str());
                return order == .gt or order == .eq;
            },
            else => return InterpreterError.NonsensicalComparisonError,
        }

        unreachable;
    }

    pub fn lessThan(lhs: Value, rhs: Value) InterpreterError!bool {
        if (!sharesType(lhs, rhs)) {
            return InterpreterError.CannotCompareValuesError;
        }

        switch (lhs) {
            .number => {
                const n1 = @field(lhs, "number");
                const n2 = @field(rhs, "number");
                return n1 == n2;
            },
            .string => {
                const s1 = @field(lhs, "string");
                const s2 = @field(rhs, "string");

                const order = std.mem.order(u8, s1.str(), s2.str());
                return order == .lt;
            },
            else => return InterpreterError.NonsensicalComparisonError,
        }

        unreachable;
    }

    pub fn lessThanOrEqual(lhs: Value, rhs: Value) InterpreterError!bool {
        if (!sharesType(lhs, rhs)) {
            return InterpreterError.CannotCompareValuesError;
        }

        switch (lhs) {
            .number => {
                const n1 = @field(lhs, "number");
                const n2 = @field(rhs, "number");
                return n1 == n2;
            },
            .string => {
                const s1 = @field(lhs, "string");
                const s2 = @field(rhs, "string");

                const order = std.mem.order(u8, s1.str(), s2.str());
                return order == .lt or order == .eq;
            },
            else => return InterpreterError.NonsensicalComparisonError,
        }

        unreachable;
    }

    pub fn format(value: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        switch (value) {
            .nil => return std.fmt.format(writer, "<nil>", .{}),
            .boolean => |b| return std.fmt.format(writer, "{}", .{b}),
            .number => |n| return std.fmt.format(writer, "{d}", .{n}),
            .string => |s| return std.fmt.format(writer, "{}", .{s.*}),
            .object => |o| return std.fmt.format(writer, "{}", .{o.*}),
        }
    }
};
