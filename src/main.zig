const std = @import("std");
const Io = std.Io;

const heap = @import("heap");

const Event = struct {
    time: f64,
    data: u64,
};

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    const io = init.io;

    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;
    

    
    const e = Event{.time =1, .data =2} ;
    var hp = heap.StructHeap(Event, .min).init();

    try hp.push(arena, e);
    try stdout_writer.flush(); // Don't forget to flush!
}

