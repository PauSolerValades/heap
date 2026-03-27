const std = @import("std");
const MultiArrayList = std.MultiArrayList;
const SegmentedMultiArrayList = @import("segmented_list.zig").SegmentedMultiArrayList;

pub fn main(init: std.process.Init) !void {
    
    const arena = init.arena.allocator();

    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), init.io, &.{});
    const stdout_writer = &stdout_file_writer.interface;

    var prng = std.Random.DefaultPrng.init(42);
    const rng = prng.random();

    const Action = struct {
        time: f64, 
        value: i32,
    };

    //const n: usize = rng.uintLessThan(usize, 10_000_000);
    
    const n = 50_000_000; // the value bitset used to hold
    try stdout_writer.print("Number of elements: {d}\n", .{n});

    const num_accesses = 250_000_000;
    try stdout_writer.print("Number of accesses: {d}\n", .{num_accesses}); 
    // Allocate a flat array to hold our random target indices
    var random_indices = try arena.alloc(usize, num_accesses);
    for (0..num_accesses) |i| {
        // Pick a random post index between 0 and n - 1
        random_indices[i] = rng.uintLessThan(usize, n); 
    }

    var l: MultiArrayList(Action) = .empty;
    // load the data
    const startTime = std.Io.Timestamp.now(init.io, .awake);
    var time: f64 = 0.0;
    const delta_t: f64 = 0.01;
    for (0..n) |i| {
        try l.append(arena, Action{ .time = time, .value = @intCast(i)}); 
        time += delta_t;
    }
    const t_1 = startTime.untilNow(init.io, .awake);   

    const c1 = std.Io.Timestamp.now(init.io, .awake);
    var acc: i64 = 0;
    
    for (random_indices) |idx| {
        acc += @intCast(l.items(.value)[idx]); 
    }
    
    const result = @as(f64, @floatFromInt(acc)) / @as(f64, @floatFromInt(num_accesses));
    const t_2 = c1.untilNow(init.io, .awake);   
    
    try stdout_writer.print("MultiArrayList - Mean: {d:.4}, Loading Time: {d}, Access time: {d}\n", .{result, t_1.toMilliseconds(), t_2.toMilliseconds()});
    try stdout_writer.flush();

    l.deinit(arena);
    
    //same but with a bookshelf
    var sl: SegmentedMultiArrayList(Action, 16) = .empty;
    defer sl.deinit(arena);
     // load the data
    const startTimeSl = std.Io.Timestamp.now(init.io, .awake);
    time = 0.0;
    for (0..n) |i| {
        try sl.append(arena, Action{ .time = time, .value = @intCast(i)}); 
    }
    const ts_1 = startTimeSl.untilNow(init.io, .awake);   


    // average it
    const cs1 = std.Io.Timestamp.now(init.io, .awake);
    var acc_sl: i64 = 0;
    
    for (random_indices) |idx| {
        acc_sl += @intCast(sl.accessField(idx, .value)); 
    }
    
    const result_sl = @as(f64, @floatFromInt(acc_sl)) / @as(f64, @floatFromInt(num_accesses));
    const ts_2 = cs1.untilNow(init.io, .awake);
    
    try stdout_writer.print("Bookshelf - Mean: {d:.4}, Loading Time: {d}, Access time: {d}\n", .{result_sl, ts_1.toMilliseconds(), ts_2.toMilliseconds()});
    try stdout_writer.flush();
}
