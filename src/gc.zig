// Copyright (c) 2022, Charly Mourglia <charly.mourglia@gmail.com>
// SPDX-License-Identifier: MIT

const std = @import("std");

const Object = @import("value.zig").Object;
const String = @import("value.zig").String;
const Value = @import("value.zig").Value;

const vm = @import("vm.zig").vm;

const Data = union(enum) {
    junked: void,
    string: *String,
    object: *Object,
};

pub const HeapId = usize;

pub const Heap = struct {
    // FIXME: We are using the allocator provided by the VM here (probably a GPA),
    // we probably need a smarter allocator though
    allocator: std.mem.Allocator,

    data: std.ArrayList(Data),
    used: std.ArrayList(bool),

    next_id: usize = 0,
    free_ids: std.AutoHashMap(HeapId, void),

    const garbage_on_each_alloc = true;

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .data = std.ArrayList(Data).init(allocator),
            .used = std.ArrayList(bool).init(allocator),
            .free_ids = std.AutoHashMap(HeapId, void).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Cleanup remaining entries
        for (self.data.items) |*data| {
            self.destroy(data);
        }
        self.free_ids.deinit();
        self.used.deinit();
        self.data.deinit();
    }

    fn destroy(self: *Self, data: *Data) void {
        switch (data.*) {
            .string => |s| {
                s.deinit();
                self.allocator.destroy(s);
            },
            .object => |o| {
                o.deinit();
                self.allocator.destroy(o);
            },
            .junked => {},
        }

        data.* = Data{ .junked = {} };
    }

    fn garbage(self: *Self) void {
        if (!vm().running) return;

        var roots = vm().gatherRoots();

        for (roots) |root| {
            self.mark(root);
        }

        for (self.used.items) |used, id| {
            if (!used) {
                self.destroy(&self.data.items[id]);
                self.free_ids.put(id, {}) catch unreachable;
            }
        }

        std.mem.set(bool, self.used.items, false);
    }

    fn mark(self: *Self, value: *const Value) void {
        switch (value.*) {
            .string => |s| self.used.items[s.id] = true,
            .object => |o| {
                if (!self.used.items[o.id]) {
                    self.used.items[o.id] = true;

                    // Recurse
                    var it = o.members.valueIterator();
                    while (it.next()) |v| {
                        self.mark(&v.*);
                    }
                }
            },
            else => {}, // Non managed data
        }
    }

    fn create(self: *Self, comptime T: type) !*T {
        if (garbage_on_each_alloc) {
            self.garbage();
        }

        const id = self.acquireId();

        // var alloc_result = self.allocator.create(T);
        if (self.allocator.create(T)) |ptr| {
            ptr.* = T.init(id, self.allocator);
            return ptr;
        } else |err| {
            // Try to garbage, then try allocating again
            self.garbage();

            var ptr = self.allocator.create(T) catch return err;
            ptr.* = T.init(id, self.allocator);
            return ptr;
        }
    }

    fn acquireId(self: *Self) HeapId {
        var id = @as(HeapId, 0);

        if (self.free_ids.count() == 0) {
            id = self.next_id;
            self.next_id += 1;
        } else {
            var it = self.free_ids.keyIterator();
            id = it.next().?.*;
            _ = self.free_ids.remove(id);
        }

        return id;
    }

    fn insertData(self: *Self, id: HeapId, data: Data) void {
        if (id >= self.data.items.len) {
            self.data.append(data) catch unreachable;
            self.used.append(false) catch unreachable;
        } else {
            self.data.items[id] = data;
        }
    }

    pub fn makeObject(self: *Self) *Object {
        var object = self.create(Object) catch unreachable;
        self.insertData(object.id, Data{ .object = object });

        return object;
    }

    pub fn makeString(self: *Self) *String {
        var string = self.create(String) catch unreachable;
        self.insertData(string.id, Data{ .string = string });

        return string;
    }

    // pub fn copyString(self: *Self, source: []const u8) HeapId {
    //     var string = Data{
    //         .string = self.alloc(u8, source.len),
    //     };

    //     std.mem.copy(u8, string.string, source);

    //     var id = self.next_id;
    //     self.next_id += 1;

    //     self.entries.put(id, Value{ .data = string }) catch unreachable; // FIXME: Same

    //     return id;
    // }
};
