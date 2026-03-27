const std = @import("std");
const MAList = std.MultiArrayList;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

/// type is the struct you wanna hold
/// n is the power of 2 which will be used as shelf_count
pub fn SegmentedMultiArrayList(comptime Book: type, comptime n: usize) type {
    const shelf_count = @as(usize, 1 << n); // lovely! 
    
    return struct {
 
        // bookshelf is the whole struct 
        // shelf is the actual list 
        // book is the item you wanna access
        bookshelf: ArrayList(MAList(Book)),
        len: usize, // elements in the bookshelf
    
        const Self = @This();

        pub const empty: Self = .{
            .bookshelf = .empty,
            .len = 0,
        };

        pub fn getShelves(self: *Self) usize {
            return self.bookshelf.items.len;
        }

        pub fn initCapacity(gpa: Allocator, shelves: usize) SegmentedMultiArrayList {
            var bookshelf: ArrayList(MAList(Book)) = try .initCapacity(gpa, shelves);
            for (0..shelves) |_| {
                bookshelf.appendAssumeCapacity(try .initCapacity(gpa, shelf_count));
            }
            return .{
                .bookshelf = bookshelf, 
                .len = 0,
            };
        }
        
        // assumes arraylist capacity, but not MAList as it's already capacitated
        pub fn append(self: *Self, gpa: Allocator, element: Book) !void {
            if (self.len == shelf_count*self.bookshelf.items.len) { // have we ran out of space?
                const new_shelf: MAList(Book) = try .initCapacity(gpa, shelf_count);
                try self.bookshelf.append(gpa, new_shelf);
            }

            const current_shelf = @as(usize, self.len >> n); // grab the most rellevant bits
            self.bookshelf.items[current_shelf].appendAssumeCapacity(element);
            self.len += 1;
        }

        pub fn access(self: *Self, i: usize) Book {
            return self.bookshelf.items[@as(usize, i >> n)].get(i & (shelf_count - 1));
        }
        
        pub fn accessField(self: *Self, i: usize, comptime field: MAList(Book).Field) @FieldType(Book, @tagName(field)) {
            const current_shelf = i >> n;
            const book = i & (shelf_count - 1);
            
            return self.bookshelf.items[current_shelf].items(field)[book];
        }
        pub fn deinit(self: *Self, gpa: Allocator) void {
            for (self.bookshelf.items) |*shelf| {
                shelf.deinit(gpa);
            }
            self.bookshelf.deinit(gpa);
        }
    };
}

const ta = std.testing.allocator;
const expect = std.testing.expect;

test "try it out :D" {
    const Element = struct {
        author: u32,
        id: u32,
    };
    const n = 4;
    var bs: SegmentedMultiArrayList(Element, n) = .empty;
    defer bs.deinit(ta);
    try expect(bs.len == 0);
    
    for (0..10000) |i| {
        const a: u32 = @intCast(i);
        const e = Element{ .author =  a, .id = a};
        try bs.append(ta, e);
    }

    const shelf_count = @as(usize, 1 << n); // lovely! 
    try expect(bs.len == 10000);
    try expect(bs.getShelves() == @as(usize, @divTrunc(10000, shelf_count)));

    const b = bs.access(10);
    try expect(b.author == 10);
    try expect(b.id == 10);

    const b2 = bs.access(524);
    try expect(b2.author == 524);
    try expect(b2.id == 524);

    const author_only = bs.accessField(10, .author);
    try expect(author_only == 10);

    const id_only = bs.accessField(10, .id);
    try expect(id_only == 10);
}
