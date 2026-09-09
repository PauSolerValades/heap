const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub fn RandomArrayList(comptime T: type) type {
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

        pub fn pop(self: *Self, rng: std.Random) ?T {
            const i = rng.uintLessThan(usize, self.elements.items.len);
            return self.elements.swapRemove(i);
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.elements.deinit(allocator);
        }
    };
}

const testing = std.testing;
const ta = testing.allocator;
const expect = testing.expect;

test "trying it out" {
    var ral: RandomArrayList(u32) = .empty;
    defer ral.deinit(ta);

    try ral.append(ta, 1);
    try ral.append(ta, 2);
    try ral.append(ta, 3);
    try ral.append(ta, 4);

    var prng: std.Random.DefaultPrng = .init(0);
    const rng = prng.random();

    const e1 = ral.remove(rng);
    const e2 = ral.remove(rng);
    const e3 = ral.remove(rng);
    const e4 = ral.remove(rng);

    try expect(e1 == 2);
    try expect(e2 == 4);
    try expect(e3 == 1);
    try expect(e4 == 3);

    try expect(ral.elements.items.len == 0);
}
