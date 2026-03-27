const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const DynamicBitSet = std.DynamicBitSetUnmanaged;

/// This modelizes a matrix with a fixed number of rows but a growable number of columns.
pub fn PagedBitSet(comptime n: usize) type {
 
    const page_count = @as(usize, 1 << n);
    
    return struct {
        pages: ArrayList(DynamicBitSet),
        N: usize,
        C: usize,
        total_items: usize, // the number of different posts (which is C*pages.items.len + offset)
        

        const Self = @This();

        pub const empty: Self = .{
            .pages = .empty,
            .total_items = 0,
            .N = 0,
            .C = page_count,
        };

        pub fn init(gpa: Allocator, N: usize) !PagedBitSet(n) {
            const bitset = try DynamicBitSet.initEmpty(gpa, N*page_count);
            var pages: ArrayList(DynamicBitSet) = try .initCapacity(gpa, 1);
            pages.appendAssumeCapacity(bitset);

            return .{
                .pages = pages,
                .N = N,
                .C = page_count,
                .total_items = 0,
            };
        }

        pub fn initPages(gpa: Allocator, N: usize, pages: usize) !PagedBitSet(n) {
            
            var p: ArrayList(DynamicBitSet) = try .initCapacity(gpa, pages);
            for (0..pages) |_| {
                const bitset = try DynamicBitSet.initEmpty(gpa, N*page_count);
                p.appendAssumeCapacity(bitset);
            }

            return .{
                .pages = p,
                .N = N,
                .C = page_count,
                .total_items = 0,
            };
        }

        pub fn initAtLeastCapacity(gpa: Allocator, N: usize, elements: usize) !PagedBitSet(n) {
          
            const pages: usize = elements >> n;
            return try initPages(gpa, N, pages + 1);
        }


        pub fn deinit(self: *Self, gpa: Allocator) void {
            for (self.pages.items) |*page| {
                page.deinit(gpa);
            }
            self.pages.deinit(gpa);
        }

        pub fn set(self: *Self, i: usize, j: usize) void {
            std.debug.assert(i >= 0 and i <= self.N);
            
            const page = @as(usize, j >> n);
            std.debug.assert(page <= self.pages.items.len);

            const j_in_page = @as(usize, j & (page_count - 1));
            self.pages.items[page].set(@as(usize, i << n) + j_in_page);
        }
        
        pub fn isSet(self: *Self, i: usize, j: usize) bool {
            std.debug.assert(i >= 0 and i <= self.N);
            const page = @as(usize, j >> n);
            std.debug.assert(page <= self.pages.items.len);

            const j_in_page = @as(usize, j & (page_count - 1));
            return self.pages.items[page].isSet(@as(usize, i << n) + j_in_page);
        }
        
        pub fn ensurePostCapacity(self: *Self, gpa: Allocator, j: usize) !void {
            const required_pages = (j >> n) + 1;
            
            while (self.pages.items.len < required_pages) {
                const bits_per_page = self.N * (1 << n);
                const new_page = try DynamicBitSet.initEmpty(gpa, bits_per_page);
                try self.pages.append(gpa, new_page);
            }
        }
    };
}

const ta = std.testing.allocator;
const expect = std.testing.expect;

test "try it out :D" {
    var pbs: PagedBitSet(4) = try .init(ta, 10); // page of 2^4
    defer pbs.deinit(ta);

    try expect(pbs.C == @as(usize, 1 << 4));
    try expect(pbs.pages.items.len == 1); // Should start with exactly 1 page

    pbs.set(0, 1);
    pbs.set(3, 1);
    pbs.set(8, 1);

    const page0 = pbs.pages.items[0];

    // user 0, post 1 -> bit = (0 * 16) + 1 = 1
    try expect(page0.isSet(1));
    try expect(pbs.isSet(0,1));
    
    // user 3, post 1 -> bit = (3 * 16) + 1 = 49
    try expect(page0.isSet(49));
    try expect(pbs.isSet(3,1)); 
    
    // user 8, post 1 -> bit = (8 * 16) + 1 = 129
    try expect(page0.isSet(129));
    try expect(pbs.isSet(8,1));

    // surrounding bits are totally clean
    try expect(!page0.isSet(0)); 
    try expect(!page0.isSet(2)); 
    try expect(!page0.isSet(48)); 
    try expect(!page0.isSet(50)); 

    try expect(!page0.isSet(128)); 
    try expect(!page0.isSet(130));

    // Trigger an allocation for a new page (Post 20)
    try pbs.ensurePostCapacity(ta, 20);
    try expect(pbs.pages.items.len == 2);

    // Set a bit on the brand new page
    pbs.set(5, 20);
    
    const page1 = pbs.pages.items[1];
    
    try expect(page1.isSet(84));
}

test "initPages" {
    // 60 posts / 16 (chunk size) = 3 full pages + 1 partial = 4 pages total
    var pbs: PagedBitSet(4) = try .initPages(ta, 10, 4);
    defer pbs.deinit(ta);

    try expect(pbs.pages.items.len == 4);

    pbs.set(1, 5);   // Page 0 
    pbs.set(2, 25);  // Page 1
    pbs.set(3, 40);  // Page 2 
    pbs.set(4, 55);  // Page 3 

    // Check Page 0: user 1, post 5 -> bit = (1 * 16) + 5 = 21
    try expect(pbs.pages.items[0].isSet(21));
    try expect(pbs.isSet(1,5));

    // Check Page 1: user 2, post 25 (offset: 25 & 15 = 9) -> bit = (2 * 16) + 9 = 41
    try expect(pbs.pages.items[1].isSet(41));
    try expect(pbs.isSet(2,25));
    
    // Check Page 2: user 3, post 40 (offset: 40 & 15 = 8) -> bit = (3 * 16) + 8 = 56
    try expect(pbs.pages.items[2].isSet(56));
    try expect(pbs.isSet(3,40));
    
    // Check Page 3: user 4, post 55 (offset: 55 & 15 = 7) -> bit = (4 * 16) + 7 = 71
    try expect(pbs.pages.items[3].isSet(71));
    try expect(pbs.isSet(4,55));
}

test "initAtLeastCapacity" {
    // same as above with the capacity done!
    var pbs: PagedBitSet(4) = try .initAtLeastCapacity(ta, 10, 60);
    defer pbs.deinit(ta);

    try expect(pbs.pages.items.len == 4);

    pbs.set(1, 5);   // Page 0 
    pbs.set(2, 25);  // Page 1
    pbs.set(3, 40);  // Page 2 
    pbs.set(4, 55);  // Page 3 

    // Check Page 0: user 1, post 5 -> bit = (1 * 16) + 5 = 21
    try expect(pbs.pages.items[0].isSet(21));
    try expect(pbs.isSet(1,5));

    // Check Page 1: user 2, post 25 (offset: 25 & 15 = 9) -> bit = (2 * 16) + 9 = 41
    try expect(pbs.pages.items[1].isSet(41));
    try expect(pbs.isSet(2,25));
    
    // Check Page 2: user 3, post 40 (offset: 40 & 15 = 8) -> bit = (3 * 16) + 8 = 56
    try expect(pbs.pages.items[2].isSet(56));
    try expect(pbs.isSet(3,40));
    
    // Check Page 3: user 4, post 55 (offset: 55 & 15 = 7) -> bit = (4 * 16) + 7 = 71
    try expect(pbs.pages.items[3].isSet(71));
    try expect(pbs.isSet(4,55));
}
