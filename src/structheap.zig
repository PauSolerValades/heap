const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const swap = std.mem.swap;

pub fn Comparators(comptime G: type) type {
    return struct {
        fn greaterThan(a: G, b: G, strict: bool) bool {
            if (strict) {
                return a > b;
            } else {
                return a >= b;
            }
        }

        fn lessThan(a: G, b: G, strict: bool) bool { return !greaterThan(a, b, strict); }
    };
}

pub const Compare = enum { min, max };

/// Implementació d'un MinHeap molt rudimentaria, però
/// (crec que) absolutament eficient.
///
/// - push: afegeix un valor al heap
/// - pop: elimina el minim del min heap
/// - peek: mostra quin és el menor valor al heap
pub fn Heap(
    comptime T: type,
    comparetype: Compare,
) type {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") @compileError("This implementation assumes a struct.\n");

    if (!@hasField(T, "time")) @compileError("No comparison key 'time' found\n");
    
    const G: type = @FieldType(T, "time");
    const type_info_G = @typeInfo(G);

    if (type_info_G != .float and type_info_G != .int ) @compileError("time key must be either an unsigned integer or a float\n");

    return struct {
        const Self = @This();

        list: std.ArrayListUnmanaged(T),
        compare: *const fn(a: G, b: G, strict: bool) bool,

        pub fn init() Self {
            return Self{
                .list = .empty,
                .compare = blk: {
                    switch (comparetype) {
                        .min => break :blk Comparators(G).lessThan,
                        .max => break :blk Comparators(G).greaterThan,
                    }
                }
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.list.deinit(allocator);
        }

        pub fn len(self: *Self) usize {
            return self.list.items.len;
        }

        fn getParentIndex(i: usize) usize {
            if (i == 0) return 0;
            return (i - 1) / 2;
        }

        fn getLeftChildIndex(i: usize) usize {
            return 2 * i + 1;
        }

        fn getRightChildIndex(i: usize) usize {
            return 2 * i + 2;
        }
        
        pub fn push(self: *Self, gpa: Allocator, value: T) !void {
            try self.list.append(gpa, value); // Adds to end, but we might overwrite it immediately
            var child_index: usize = self.list.items.len - 1;
            
            // Optimization: Store the value we are bubbling up
            const new_item = self.list.items[child_index]; 
            const new_time = new_item.time;

            while (child_index > 0) {
                const parent_index = getParentIndex(child_index);
                const parent_item = self.list.items[parent_index];
                
                // if (new_time >= parent_item.time) break;
                if ( !self.compare(new_time, parent_item.time, false) ) break;

                // Shift parent down into the child's spot
                self.list.items[child_index] = parent_item;
                child_index = parent_index;
            }
            
            // Place our item in its final home
            self.list.items[child_index] = new_item;
        }

        pub fn pop(self: *Self) ?T {
            if (self.list.items.len == 0) return null;

            const min = self.list.items[0];

            const last_item = self.list.pop().?; // Removes from end. will be non empty, 
            
            if (self.list.items.len == 0) return min;

            // the "Hole" optimization starts at the root (index 0)
            var parent_index: usize = 0;
            const half_len = self.list.items.len / 2; // only check parents
            
            while (parent_index < half_len) {
                var child_index = getLeftChildIndex(parent_index);
                const right_index = getRightChildIndex(parent_index);
    
                // Find the smaller child
                if (right_index < self.list.items.len and 
                    self.list.items[right_index].time < self.list.items[child_index].time) 
                {
                    child_index = right_index;
                }

                // If the last_item fits here (is smaller than the smallest child), we stop.
                if ( self.compare(last_item.time, self.list.items[child_index].time, false) ) break;
                //if (last_item.time <= self.list.items[child_index].time) break;

                // Otherwise, move the child UP into the hole
                self.list.items[parent_index] = self.list.items[child_index];
                
                // The hole moves down to the child's spot
                parent_index = child_index;
            }

            self.list.items[parent_index] = last_item;

            return min;
        }

        pub fn peek(self: *Self) ?T {
            if (self.list.items.len == 0) return null;
            return self.list.items[0];
        }
    };
}

const Task = struct {
    time: i32, // The heap requires this!
    id: u32 = 0, // Extra data to prove we carry payload
};

test "MinHeap Integers" {
    const a = std.testing.allocator;

    var heap = Heap(Task, .min).init();
    defer heap.deinit(a);

    try heap.push(a, Task{ .time = 10, .id = 100 });
    try heap.push(a, Task{ .time = 5, .id = 200 });
    try heap.push(a, Task{ .time = 20, .id = 300 });
    try heap.push(a, Task{ .time = 2, .id = 400 });

    try std.testing.expectEqual(@as(i32, 2), heap.pop().?.time);
    try std.testing.expectEqual(@as(i32, 5), heap.pop().?.time);
    try std.testing.expectEqual(@as(i32, 10), heap.pop().?.time);
    try std.testing.expectEqual(@as(i32, 20), heap.pop().?.time);

    try std.testing.expect(heap.pop() == null);
}

test "MinHeap - Edge Cases (Struct)" {
    const a = std.testing.allocator;
    var heap = Heap(Task, .min).init();
    defer heap.deinit(a);

    // 1. Pop from empty
    try std.testing.expect(heap.pop() == null);

    // 2. Single Element
    try heap.push(a, Task{ .time = 42 });
    try std.testing.expectEqual(@as(i32, 42), heap.pop().?.time);

    try std.testing.expect(heap.pop() == null);

    // 3. Negative Times
    try heap.push(a, Task{ .time = -5 });
    try heap.push(a, Task{ .time = -10 });
    try heap.push(a, Task{ .time = 0 });

    try std.testing.expectEqual(@as(i32, -10), heap.pop().?.time);
    try std.testing.expectEqual(@as(i32, -5), heap.pop().?.time);
    try std.testing.expectEqual(@as(i32, 0), heap.pop().?.time);
}

test "MinHeap - Duplicates (Struct)" {
    const a = std.testing.allocator;
    var heap = Heap(Task, .min).init();
    defer heap.deinit(a);

    // Push duplicates
    try heap.push(a, Task{ .time = 5, .id = 1 });
    try heap.push(a, Task{ .time = 1, .id = 2 });
    try heap.push(a, Task{ .time = 5, .id = 3 });

    // Expect: 1, then 5, then 5
    const first = heap.pop().?;
    try std.testing.expectEqual(@as(i32, 1), first.time);

    const second = heap.pop().?;
    try std.testing.expectEqual(@as(i32, 5), second.time);

    const third = heap.pop().?;
    try std.testing.expectEqual(@as(i32, 5), third.time);
}
