const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const swap = std.mem.swap; // We will use this for the primitive swaps

pub fn Heap(comptime T: type) type {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") @compileError("Just structs allowed.\n");
    if (!@hasField(T, "time")) @compileError("No comparison key 'time' found\n");

    return struct {
        const Self = @This();
        list: std.MultiArrayList(T),

        pub fn init() Self {
            return Self{ .list = .empty };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.list.deinit(allocator);
        }

        pub fn len(self: *Self) usize {
            return self.list.len;
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

        // --- THE NEW HELPER FUNCTION ---
        // This generates optimized code to swap specific indices in EVERY array.
        fn swapItems(self: *Self, a: usize, b: usize) void {
            const slice = self.list.slice();
            // We iterate over every field in the struct T (time, type, id)
            inline for (std.meta.fields(T)) |field_info| {
                // 1. Get the enum for this field (required by MultiArrayList)
                const f_enum = @field(std.MultiArrayList(T).Field, field_info.name);
                
                // 2. Get the specific array for this field (e.g., just the IDs)
                const array = slice.items(f_enum);
                
                // 3. Swap just these two values directly in memory
                swap(field_info.type, &array[a], &array[b]);
            }
        }

     pub fn push(self: *Self, gpa: Allocator, value: T) !void {
        try self.list.append(gpa, value);
        var child_index: usize = self.list.len - 1;

        // 1. Save the NEW item's fields to stack variables (The "Floating" Item)
        // We can use a temp struct, or just variables if we want to be explicit.
        const new_item = value; 

        const times = self.list.items(.time);
        // We need the slice for the other fields too to shift them efficiently
        // Assuming your Event struct has: time, type, id
        const types = self.list.items(.type);
        const ids = self.list.items(.id);

        while (child_index > 0) {
            const parent_index = getParentIndex(child_index);
            const parent_time = times[parent_index];

            // Compare against our floating item's time
            if (new_item.time >= parent_time) break;

            // Instead of swapping, we just overwrite the child slot with the parent's data
            times[child_index] = times[parent_index];
            types[child_index] = types[parent_index];
            ids[child_index]   = ids[parent_index];

            child_index = parent_index;
        }

        times[child_index] = new_item.time;
        types[child_index] = new_item.type;
        ids[child_index]   = new_item.id;
    }        

    pub fn pop(self: *Self) ?T {
        if (self.list.len == 0) return null;

        const min = self.list.get(0);

        const last_val = self.list.pop().?;

        if (self.list.len == 0) return min;

        var parent_index: usize = 0;
        const slice = self.list.slice();
        
        const times = slice.items(.time);
        const half_len = self.list.len / 2;

        while (parent_index < half_len) {
            var child_index = getLeftChildIndex(parent_index);
            const right_index = getRightChildIndex(parent_index);

            // Find the smaller child
            if (right_index < self.list.len and 
                times[right_index] < times[child_index]) 
            {
                child_index = right_index;
            }

            if (last_val.time <= times[child_index]) break;

            // We write the child's values into the parent's slot (the current hole)
            inline for (std.meta.fields(T)) |field_info| {
                const f_enum = @field(std.MultiArrayList(T).Field, field_info.name);
                const array = slice.items(f_enum);
                array[parent_index] = array[child_index];
            }

            parent_index = child_index;
        }

        inline for (std.meta.fields(T)) |field_info| {
            const f_enum = @field(std.MultiArrayList(T).Field, field_info.name);
            const array = slice.items(f_enum);
            array[parent_index] = @field(last_val, field_info.name);
        }

        return min;
    }
 
    pub fn peek(self: *Self) ?T {
            if (self.list.len == 0) return null;
            return self.list.get(0);
        }
    };
}

const Task = struct {
    time: i32,      // The heap requires this!
    id: u32 = 0,    // Extra data to prove we carry payload
};

test "MinHeap Integers" {
    const a = std.testing.allocator;

    var heap = Heap(Task).init();
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
    var heap = Heap(Task).init();
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
    var heap = Heap(Task).init();
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
