//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;


pub const StructHeap = @import("structheap.zig").Heap;
