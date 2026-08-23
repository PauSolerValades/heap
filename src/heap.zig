const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const Order = std.math.Order;

pub fn Heap(comptime T: type, comptime Context: type, comptime compareFn: fn (context: Context, a: T, b: T) Order) type {
    return DaryHeap(T, 2, Context, compareFn);
}
// this code has been adapted from the std.PriorityQueue implementation

/// Heap data structure for storing generic data. Initialize with empty.
/// if no context is provided, and with `init(context)` if there is.
/// Provide `compareFn` that returns `Order.lt` when its second
/// argument should get popped before its third argument,
/// `Order.eq` if the arguments are of equal priority, or `Order.gt`
/// if the third argument should be popped first.
/// For example, to make `pop` return the smallest number, provide
/// `fn lessThan(context: void, a: T, b: T) Order { _ = context; return std.math.order(a, b); }`
pub fn DaryHeap(comptime T: type, d: usize, comptime Context: type, comptime compareFn: fn (context: Context, a: T, b: T) Order) type {
    return struct {
        const Self = @This();

        items: []T,
        capacity: usize,
        context: Context,
        d: usize,

        /// checks if T is a struct. If it isnt we have to avoid
        /// checking for the @hasField
        const is_intrusive = blk: {
            if (@typeInfo(T) == .@"struct") {
                break :blk @hasField(T, "heap_index");
            }
            break :blk false;
        };

        /// Done for the intrusive event in heap. If the struct is
        inline fn writeItem(self: *Self, index: usize, item: T) void {
            self.items[index] = item;
            if (is_intrusive) {
                self.items[index].heap_index = index;
            }
        }

        pub fn init(context: Context) Self {
            return .{
                .items = &.{},
                .capacity = 0,
                .context = context,
                .d = d,
            };
        }

        pub const empty: Self = if (@sizeOf(Context) == 0) .{
            .items = &.{},
            .capacity = 0,
            .context = {},
            .d = d,
        } else @compileError("Cannot use empty with a non-void context. Use .init(context");

        /// Free memory used by the queue.
        pub fn deinit(self: Self, gpa: Allocator) void {
            gpa.free(self.allocatedSlice());
            // self.* = undefined;
        }

        fn addUnchecked(self: *Self, elem: T) void {
            self.items.len += 1;
            self.writeItem(self.items.len - 1, elem);
            siftUp(self, self.items.len - 1);
        }

        fn siftUp(self: *Self, start_index: usize) void {
            const child = self.items[start_index];
            var child_index = start_index;
            while (child_index > 0) {
                // const parent_index = ((child_index - 1) >> 1); // for d = 2
                const parent_index = ((child_index - 1) / self.d);
                const parent = self.items[parent_index];
                if (compareFn(self.context, child, parent) != .lt) break;

                self.writeItem(child_index, parent);

                child_index = parent_index;
            }
            self.writeItem(child_index, child);
        }

        /// Add each element in `items` to the queue.
        pub fn addSlice(self: *Self, gpa: Allocator, items: []const T) error{OutOfMemory}!void {
            try self.ensureUnusedCapacity(gpa, items.len);
            for (items) |e| {
                self.addUnchecked(e);
            }
        }

        /// Look at the highest priority element in the queue. Returns
        /// `null` if empty.
        pub fn peek(self: *Self) ?T {
            return if (self.items.len > 0) self.items[0] else null;
        }

        /// Remove and return the highest priority element from the
        /// queue.
        pub fn pop(self: *Self) T {
            return self.removeIndex(0);
        }

        /// Insert a new element, maintaining priority.
        pub fn push(self: *Self, gpa: Allocator, elem: T) error{OutOfMemory}!void {
            try self.ensureUnusedCapacity(gpa, 1);
            addUnchecked(self, elem);
        }

        /// Pop the highest priority element from the queue. Returns
        /// `null` if empty.
        pub fn removeOrNull(self: *Self) ?T {
            return if (self.items.len > 0) self.pop() else null;
        }

        /// Remove and return element at index. Indices are in the
        /// same order as iterator, which is not necessarily priority
        /// order.
        pub fn removeIndex(self: *Self, index: usize) T {
            assert(self.items.len > index);

            const last = self.items[self.items.len - 1];
            const item = self.items[index];

            self.writeItem(index, last);
            //self.items[index] = last;
            self.items.len -= 1;

            if (index == self.items.len) {
                // Last element removed, nothing more to do.
            } else if (index == 0) {
                siftDown(self, index);
            } else {
                const parent_index = ((index - 1) / self.d);
                const parent = self.items[parent_index];
                if (compareFn(self.context, last, parent) == .gt) {
                    siftDown(self, index);
                } else {
                    siftUp(self, index);
                }
            }

            return item;
        }

        /// Return the number of elements remaining in the heap
        pub fn count(self: Self) usize {
            return self.items.len;
        }

        /// Returns a slice of all the items plus the extra capacity, whose memory
        /// contents are `undefined`.
        fn allocatedSlice(self: Self) []T {
            // `items.len` is the length, not the capacity.
            return self.items.ptr[0..self.capacity];
        }

        fn siftDown(self: *Self, target_index: usize) void {
            const target_element = self.items[target_index];
            var index = target_index;
            while (true) {
                const first_child_i = (std.math.mul(usize, index, d) catch break) + 1;
                if (!(first_child_i < self.items.len)) break;

                var lesser_child_i = first_child_i;
                var current_child_i = first_child_i + 1;

                const end_child_i = @min(self.items.len, first_child_i + d);

                while (current_child_i < end_child_i) : (current_child_i += 1) {
                    if (compareFn(self.context, self.items[current_child_i], self.items[lesser_child_i]) == .lt) {
                        lesser_child_i = current_child_i;
                    }
                }
                if (compareFn(self.context, target_element, self.items[lesser_child_i]) == .lt) break;

                self.writeItem(index, self.items[lesser_child_i]);

                index = lesser_child_i;
            }
            self.writeItem(index, target_element);
        }

        /// PriorityQueue takes ownership of the passed in slice. The slice must have been
        /// allocated with `allocator`.
        /// Deinitialize with `deinit`.
        pub fn fromOwnedSlice(items: []T, context: Context) Self {
            var self = Self{
                .items = items,
                .capacity = items.len,
                .context = context,
                .d = d,
            };

            var i = self.items.len >> 1;
            while (i > 0) {
                i -= 1;
                self.siftDown(i);
            }
            return self;
        }

        /// Ensure that the queue can fit at least `new_capacity` items.
        pub fn ensureTotalCapacity(self: *Self, gpa: Allocator, new_capacity: usize) !void {
            var better_capacity = self.capacity;
            if (better_capacity >= new_capacity) return;
            while (true) {
                better_capacity += better_capacity / 2 + 8;
                if (better_capacity >= new_capacity) break;
            }
            try self.ensureTotalCapacityPrecise(gpa, better_capacity);
        }

        pub fn ensureTotalCapacityPrecise(self: *Self, gpa: Allocator, new_capacity: usize) error{OutOfMemory}!void {
            if (self.capacity >= new_capacity) return;

            const old_memory = self.allocatedSlice();
            const new_memory = try gpa.realloc(old_memory, new_capacity);
            self.items.ptr = new_memory.ptr;
            self.capacity = new_memory.len;
        }

        /// Ensure that the queue can fit at least `additional_count` **more** item.
        pub fn ensureUnusedCapacity(self: *Self, gpa: Allocator, additional_count: usize) error{OutOfMemory}!void {
            return try self.ensureTotalCapacity(gpa, self.items.len + additional_count);
        }

        /// Reduce allocated capacity to `new_capacity`.
        pub fn shrinkAndFree(self: *Self, gpa: Allocator, new_capacity: usize) void {
            assert(new_capacity <= self.capacity);

            // Cannot shrink to smaller than the current queue size without invalidating the heap property
            assert(new_capacity >= self.items.len);

            const old_memory = self.allocatedSlice();
            const new_memory = gpa.realloc(old_memory, new_capacity) catch |e| switch (e) {
                error.OutOfMemory => { // no problem, capacity is still correct then.
                    return;
                },
            };

            self.items.ptr = new_memory.ptr;
            self.capacity = new_memory.len;
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.items.len = 0;
        }

        pub fn clearAndFree(self: *Self, gpa: Allocator) void {
            gpa.free(self.allocatedSlice());
            self.items.len = 0;
            self.cap = 0;
        }

        pub fn update(self: *Self, elem: T, new_elem: T) !void {
            const update_index = blk: {
                var idx: usize = 0;
                while (idx < self.items.len) : (idx += 1) {
                    const item = self.items[idx];
                    if (compareFn(self.context, item, elem) == .eq) break :blk idx;
                }
                return error.ElementNotFound;
            };
            const old_elem: T = self.items[update_index];
            self.items[update_index] = new_elem;
            switch (compareFn(self.context, new_elem, old_elem)) {
                .lt => siftUp(self, update_index),
                .gt => siftDown(self, update_index),
                .eq => {}, // Nothing to do as the items have equal priority
            }
        }

        pub const Iterator = struct {
            queue: *Heap(T, Context, compareFn),
            count: usize,

            pub fn next(it: *Iterator) ?T {
                if (it.count >= it.queue.items.len) return null;
                const out = it.count;
                it.count += 1;
                return it.queue.items[out];
            }

            pub fn reset(it: *Iterator) void {
                it.count = 0;
            }
        };

        /// Return an iterator that walks the queue without consuming
        /// it. The iteration order may differ from the priority order.
        /// Invalidated if the heap is modified.
        pub fn iterator(self: *Self) Iterator {
            return Iterator{
                .queue = self,
                .count = 0,
            };
        }

        fn dump(self: *Self) void {
            const print = std.debug.print;
            print("{{ ", .{});
            print("items: ", .{});
            for (self.items) |e| {
                print("{}, ", .{e});
            }
            print("array: ", .{});
            for (self.items) |e| {
                print("{}, ", .{e});
            }
            print("len: {} ", .{self.items.len});
            print("capacity: {}", .{self.cap});
            print(" }}\n", .{});
        }
    };
}

fn lessThan(context: void, a: u32, b: u32) Order {
    _ = context;
    return std.math.order(a, b);
}

fn greaterThan(context: void, a: u32, b: u32) Order {
    return lessThan(context, a, b).invert();
}

const PQlt = Heap(u32, void, lessThan);
const PQgt = Heap(u32, void, greaterThan);

const testing = std.testing;

const ta = testing.allocator;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectError = testing.expectError;

test "add and remove min heap" {
    var queue: PQlt = .empty;
    defer queue.deinit(ta);

    try queue.push(ta, 54);
    try queue.push(ta, 12);
    try queue.push(ta, 7);
    try queue.push(ta, 23);
    try queue.push(ta, 25);
    try queue.push(ta, 13);
    try expectEqual(@as(u32, 7), queue.pop());
    try expectEqual(@as(u32, 12), queue.pop());
    try expectEqual(@as(u32, 13), queue.pop());
    try expectEqual(@as(u32, 23), queue.pop());
    try expectEqual(@as(u32, 25), queue.pop());
    try expectEqual(@as(u32, 54), queue.pop());
}

test "add and remove same min heap" {
    var queue: PQlt = .empty;
    defer queue.deinit(ta);

    try queue.push(ta, 1);
    try queue.push(ta, 1);
    try queue.push(ta, 2);
    try queue.push(ta, 2);
    try queue.push(ta, 1);
    try queue.push(ta, 1);
    try expectEqual(@as(u32, 1), queue.pop());
    try expectEqual(@as(u32, 1), queue.pop());
    try expectEqual(@as(u32, 1), queue.pop());
    try expectEqual(@as(u32, 1), queue.pop());
    try expectEqual(@as(u32, 2), queue.pop());
    try expectEqual(@as(u32, 2), queue.pop());
}

test "removeOrNull on empty" {
    var queue: PQlt = .empty;
    defer queue.deinit(ta);

    try expect(queue.removeOrNull() == null);
}

test "edge case 3 elements" {
    var queue: PQlt = .empty;
    defer queue.deinit(ta);

    try queue.push(ta, 9);
    try queue.push(ta, 3);
    try queue.push(ta, 2);
    try expectEqual(@as(u32, 2), queue.pop());
    try expectEqual(@as(u32, 3), queue.pop());
    try expectEqual(@as(u32, 9), queue.pop());
}

test "peek" {
    var queue: PQlt = .empty;
    defer queue.deinit(ta);

    try expect(queue.peek() == null);
    try queue.push(ta, 9);
    try queue.push(ta, 3);
    try queue.push(ta, 2);
    try expectEqual(@as(u32, 2), queue.peek().?);
    try expectEqual(@as(u32, 2), queue.peek().?);
}

test "sift up with odd indices" {
    var queue: PQlt = .empty;
    defer queue.deinit(ta);
    const items = [_]u32{ 15, 7, 21, 14, 13, 22, 12, 6, 7, 25, 5, 24, 11, 16, 15, 24, 2, 1 };
    for (items) |e| {
        try queue.push(ta, e);
    }

    const sorted_items = [_]u32{ 1, 2, 5, 6, 7, 7, 11, 12, 13, 14, 15, 15, 16, 21, 22, 24, 24, 25 };
    for (sorted_items) |e| {
        try expectEqual(e, queue.pop());
    }
}

test "addSlice" {
    var queue: PQlt = .empty;
    defer queue.deinit(ta);
    const items = [_]u32{ 15, 7, 21, 14, 13, 22, 12, 6, 7, 25, 5, 24, 11, 16, 15, 24, 2, 1 };
    try queue.addSlice(ta, items[0..]);

    const sorted_items = [_]u32{ 1, 2, 5, 6, 7, 7, 11, 12, 13, 14, 15, 15, 16, 21, 22, 24, 24, 25 };
    for (sorted_items) |e| {
        try expectEqual(e, queue.pop());
    }
}

test "fromOwnedSlice trivial case 0" {
    const items = [0]u32{};
    const queue_items = try ta.dupe(u32, &items);
    var queue = PQlt.fromOwnedSlice(queue_items[0..], {});
    defer queue.deinit(ta);
    try expectEqual(@as(usize, 0), queue.count());
    try expect(queue.removeOrNull() == null);
}

test "fromOwnedSlice trivial case 1" {
    const items = [1]u32{1};
    const queue_items = try ta.dupe(u32, &items);
    var queue = PQlt.fromOwnedSlice(queue_items[0..], {});
    defer queue.deinit(ta);

    try expectEqual(@as(usize, 1), queue.count());
    try expectEqual(items[0], queue.pop());
    try expect(queue.removeOrNull() == null);
}

test "fromOwnedSlice" {
    const items = [_]u32{ 15, 7, 21, 14, 13, 22, 12, 6, 7, 25, 5, 24, 11, 16, 15, 24, 2, 1 };
    const heap_items = try ta.dupe(u32, items[0..]);
    var queue = PQlt.fromOwnedSlice(heap_items[0..], {});
    defer queue.deinit(ta);

    const sorted_items = [_]u32{ 1, 2, 5, 6, 7, 7, 11, 12, 13, 14, 15, 15, 16, 21, 22, 24, 24, 25 };
    for (sorted_items) |e| {
        try expectEqual(e, queue.pop());
    }
}

test "add and remove max heap" {
    var queue: PQgt = .empty;
    defer queue.deinit(ta);

    try queue.push(ta, 54);
    try queue.push(ta, 12);
    try queue.push(ta, 7);
    try queue.push(ta, 23);
    try queue.push(ta, 25);
    try queue.push(ta, 13);
    try expectEqual(@as(u32, 54), queue.pop());
    try expectEqual(@as(u32, 25), queue.pop());
    try expectEqual(@as(u32, 23), queue.pop());
    try expectEqual(@as(u32, 13), queue.pop());
    try expectEqual(@as(u32, 12), queue.pop());
    try expectEqual(@as(u32, 7), queue.pop());
}

test "add and remove same max heap" {
    var queue: PQgt = .empty;
    defer queue.deinit(ta);

    try queue.push(ta, 1);
    try queue.push(ta, 1);
    try queue.push(ta, 2);
    try queue.push(ta, 2);
    try queue.push(ta, 1);
    try queue.push(ta, 1);
    try expectEqual(@as(u32, 2), queue.pop());
    try expectEqual(@as(u32, 2), queue.pop());
    try expectEqual(@as(u32, 1), queue.pop());
    try expectEqual(@as(u32, 1), queue.pop());
    try expectEqual(@as(u32, 1), queue.pop());
    try expectEqual(@as(u32, 1), queue.pop());
}

test "iterator" {
    var queue: PQlt = .empty;
    var map = std.AutoHashMap(u32, void).init(testing.allocator);
    defer {
        queue.deinit(ta);
        map.deinit();
    }

    const items = [_]u32{ 54, 12, 7, 23, 25, 13 };
    for (items) |e| {
        _ = try queue.push(ta, e);
        try map.put(e, {});
    }

    var it = queue.iterator();
    while (it.next()) |e| {
        _ = map.remove(e);
    }

    try expectEqual(@as(usize, 0), map.count());
}

test "remove at index" {
    var queue: PQlt = .empty;
    defer queue.deinit(ta);

    const items = [_]u32{ 2, 1, 8, 9, 3, 4, 5 };
    for (items) |e| {
        _ = try queue.push(ta, e);
    }

    var it = queue.iterator();
    var idx: usize = 0;
    const two_idx = while (it.next()) |elem| {
        if (elem == 2)
            break idx;
        idx += 1;
    } else unreachable;
    const sorted_items = [_]u32{ 1, 3, 4, 5, 8, 9 };
    try expectEqual(queue.removeIndex(two_idx), 2);

    var i: usize = 0;
    while (queue.removeOrNull()) |n| : (i += 1) {
        try expectEqual(n, sorted_items[i]);
    }
    try expectEqual(queue.removeOrNull(), null);
}

test "iterator while empty" {
    var queue: PQlt = .empty;
    defer queue.deinit(ta);

    var it = queue.iterator();

    try expectEqual(it.next(), null);
}

test "shrinkAndFree" {
    var queue: PQlt = .empty;
    defer queue.deinit(ta);

    try queue.ensureTotalCapacity(ta, 4);
    try expect(queue.capacity >= 4);

    try queue.push(ta, 1);
    try queue.push(ta, 2);
    try queue.push(ta, 3);
    try expect(queue.capacity >= 4);
    try expectEqual(@as(usize, 3), queue.count());

    queue.shrinkAndFree(ta, 3);
    try expectEqual(@as(usize, 3), queue.capacity);
    try expectEqual(@as(usize, 3), queue.count());

    try expectEqual(@as(u32, 1), queue.pop());
    try expectEqual(@as(u32, 2), queue.pop());
    try expectEqual(@as(u32, 3), queue.pop());
    try expect(queue.removeOrNull() == null);
}

test "update min heap" {
    var queue: PQlt = .empty;
    defer queue.deinit(ta);

    try queue.push(ta, 55);
    try queue.push(ta, 44);
    try queue.push(ta, 11);
    try queue.update(55, 5);
    try queue.update(44, 4);
    try queue.update(11, 1);
    try expectEqual(@as(u32, 1), queue.pop());
    try expectEqual(@as(u32, 4), queue.pop());
    try expectEqual(@as(u32, 5), queue.pop());
}

test "update same min heap" {
    var queue: PQlt = .empty;
    defer queue.deinit(ta);

    try queue.push(ta, 1);
    try queue.push(ta, 1);
    try queue.push(ta, 2);
    try queue.push(ta, 2);
    try queue.update(1, 5);
    try queue.update(2, 4);
    try expectEqual(@as(u32, 1), queue.pop());
    try expectEqual(@as(u32, 2), queue.pop());
    try expectEqual(@as(u32, 4), queue.pop());
    try expectEqual(@as(u32, 5), queue.pop());
}

test "update max heap" {
    var queue: PQgt = .empty;
    defer queue.deinit(ta);

    try queue.push(ta, 55);
    try queue.push(ta, 44);
    try queue.push(ta, 11);
    try queue.update(55, 5);
    try queue.update(44, 1);
    try queue.update(11, 4);
    try expectEqual(@as(u32, 5), queue.pop());
    try expectEqual(@as(u32, 4), queue.pop());
    try expectEqual(@as(u32, 1), queue.pop());
}

test "update same max heap" {
    var queue: PQgt = .empty;
    defer queue.deinit(ta);

    try queue.push(ta, 1);
    try queue.push(ta, 1);
    try queue.push(ta, 2);
    try queue.push(ta, 2);
    try queue.update(1, 5);
    try queue.update(2, 4);
    try expectEqual(@as(u32, 5), queue.pop());
    try expectEqual(@as(u32, 4), queue.pop());
    try expectEqual(@as(u32, 2), queue.pop());
    try expectEqual(@as(u32, 1), queue.pop());
}

test "update after remove" {
    var queue: PQlt = .empty;
    defer queue.deinit(ta);

    try queue.push(ta, 1);
    try expectEqual(@as(u32, 1), queue.pop());
    try expectError(error.ElementNotFound, queue.update(1, 1));
}

test "siftUp in remove" {
    var queue: PQlt = .empty;
    defer queue.deinit(ta);

    try queue.addSlice(ta, &.{ 0, 1, 100, 2, 3, 101, 102, 4, 5, 6, 7, 103, 104, 105, 106, 8 });

    _ = queue.removeIndex(std.mem.findScalar(u32, queue.items[0..queue.count()], 102).?);

    const sorted_items = [_]u32{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 100, 101, 103, 104, 105, 106 };
    for (sorted_items) |e| {
        try expectEqual(e, queue.pop());
    }
}

fn contextLessThan(context: []const u32, a: usize, b: usize) Order {
    return std.math.order(context[a], context[b]);
}

const CPQlt = Heap(usize, []const u32, contextLessThan);

test "add and remove min heap with context comparator" {
    const context = [_]u32{ 5, 3, 4, 2, 2, 8, 0 };

    var queue = CPQlt.init(context[0..]);
    defer queue.deinit(ta);

    try queue.push(ta, 0);
    try queue.push(ta, 1);
    try queue.push(ta, 2);
    try queue.push(ta, 3);
    try queue.push(ta, 4);
    try queue.push(ta, 5);
    try queue.push(ta, 6);
    try expectEqual(@as(usize, 6), queue.pop());
    try expectEqual(@as(usize, 4), queue.pop());
    try expectEqual(@as(usize, 3), queue.pop());
    try expectEqual(@as(usize, 1), queue.pop());
    try expectEqual(@as(usize, 2), queue.pop());
    try expectEqual(@as(usize, 0), queue.pop());
    try expectEqual(@as(usize, 5), queue.pop());
}

fn lessThanEvent(context: void, a: Event, b: Event) Order {
    _ = context;
    return std.math.order(a.priority, b.priority);
}

const Event = struct {
    heap_index: usize = 0,
    priority: f64,
};

const EHlt = Heap(Event, void, lessThanEvent);

test "intrusive behaviour" {
    var queue: EHlt = .empty;
    defer queue.deinit(ta);

    const e1 = Event{ .priority = 1 };
    const e2 = Event{ .priority = 2 };
    const e3 = Event{ .priority = 3 };
    const e4 = Event{ .priority = 4 };

    try queue.push(ta, e4);
    try queue.push(ta, e3);
    try queue.push(ta, e2);
    try queue.push(ta, e1);
    try expectEqual(@as(f64, 1), queue.pop().priority);
    try expectEqual(@as(f64, 2), queue.pop().priority);
    try expectEqual(@as(f64, 3), queue.pop().priority);
    try expectEqual(@as(f64, 4), queue.pop().priority);
}

test "add and remove min heap multpile leafs" {
    inline for (.{ 2, 3, 4, 8 }) |d| {
        const DHlt = DaryHeap(u32, d, void, lessThan);
        var queue: DHlt = .empty;
        defer queue.deinit(ta);

        try queue.push(ta, 54);
        try queue.push(ta, 12);
        try queue.push(ta, 7);
        try queue.push(ta, 23);
        try queue.push(ta, 25);
        try queue.push(ta, 13);
        try expectEqual(@as(u32, 7), queue.pop());
        try expectEqual(@as(u32, 12), queue.pop());
        try expectEqual(@as(u32, 13), queue.pop());
        try expectEqual(@as(u32, 23), queue.pop());
        try expectEqual(@as(u32, 25), queue.pop());
        try expectEqual(@as(u32, 54), queue.pop());
    }
}

test "add and remove same min heap multpile leafs" {
    inline for (.{ 3, 4, 8 }) |d| {
        const DHlt = DaryHeap(u32, d, void, lessThan);
        var queue: DHlt = .empty;
        defer queue.deinit(ta);

        try queue.push(ta, 1);
        try queue.push(ta, 1);
        try queue.push(ta, 2);
        try queue.push(ta, 2);
        try queue.push(ta, 1);
        try queue.push(ta, 1);
        try expectEqual(@as(u32, 1), queue.pop());
        try expectEqual(@as(u32, 1), queue.pop());
        try expectEqual(@as(u32, 1), queue.pop());
        try expectEqual(@as(u32, 1), queue.pop());
        try expectEqual(@as(u32, 2), queue.pop());
        try expectEqual(@as(u32, 2), queue.pop());
    }
}

test "edge case 3 elements multpile leafs" {
    inline for (.{ 2, 3, 4, 8 }) |d| {
        const DHlt = DaryHeap(u32, d, void, lessThan);
        var queue: DHlt = .empty;
        defer queue.deinit(ta);

        try queue.push(ta, 9);
        try queue.push(ta, 3);
        try queue.push(ta, 2);
        try expectEqual(@as(u32, 2), queue.pop());
        try expectEqual(@as(u32, 3), queue.pop());
        try expectEqual(@as(u32, 9), queue.pop());
    }
}
