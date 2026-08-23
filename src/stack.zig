const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub fn Stack(comptime T: type) type {
    return struct {
        elements: ArrayList(T),

        const Self = @This();

        pub const empty: Self = .{
            .elements = .empty,
        };

        pub fn initCapacity(allocator: Allocator, capacity: usize) Allocator.Error!Self {
            return .{
                .elements = try ArrayList(T).initCapacity(allocator, capacity),
            };
        }

        pub fn push(self: *Self, allocator: Allocator, element: T) Allocator.Error!void {
            try self.elements.append(allocator, element);
        }

        pub fn pop(self: *Self) ?T {
            return self.elements.pop();
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.elements.deinit(allocator);
        }
    };
}

const testing = std.testing;
const expectEqual = testing.expectEqual;

test "push and pop" {
    var stack = try Stack(u32).initCapacity(testing.allocator, 0);
    defer stack.deinit(testing.allocator);

    try stack.push(testing.allocator, 1);
    try stack.push(testing.allocator, 2);
    try stack.push(testing.allocator, 3);

    try expectEqual(@as(?u32, 3), stack.pop());
    try expectEqual(@as(?u32, 2), stack.pop());
    try expectEqual(@as(?u32, 1), stack.pop());
    try expectEqual(@as(?u32, null), stack.pop());
}

test "empty stack pops null" {
    var stack: Stack(u32) = .empty;
    defer stack.deinit(testing.allocator);

    try expectEqual(@as(?u32, null), stack.pop());
}
