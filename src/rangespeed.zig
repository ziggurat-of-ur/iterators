const std = @import("std");
const iterators = @import("iterators.zig");

//const test_loops = 100_000;
var test_loops: u64 = 10000;

fn standardLoop() void {
    var n: u64 = 0;

    while (n < test_loops) : (n += 1) {
        asm volatile (""
            :
            :
            : "memory"
        );
    }
}

fn iterLoop() !void {
    var range = try iterators.Range(u64).init(0, test_loops, 1);
    var iter = &range.iterator;
    while (iter.next()) |_| {
        asm volatile (""
            :
            :
            : "memory"
        );
    }
}

fn hackyFastLoop() !void {
    const Range = iterators.Range(u64);
    var range = try Range.init(0, test_loops, 1);
    var iter = &range.iterator;
    while (Range.next(iter)) |_| {
        asm volatile (""
            :
            :
            : "memory"
        );
    }
}

pub fn main() anyerror!void {
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    for (args) |arg| {
        try stdout.print("arg {}\n", .{arg});
        test_loops = std.fmt.parseInt(u64, arg, 10) catch test_loops;
    }

    try stdout.print("Rangetest {}\n", .{test_loops});

    // Range comparison
    var n: u64 = 0;
    const start = std.time.nanoTimestamp();
    while (n < test_loops) : (n += 1) {
        standardLoop();
    }
    const end = std.time.nanoTimestamp();
    try stdout.print("Normal Zig-style: {}ns\n", .{(end - start)});

    n = 0;
    const iterstart = std.time.nanoTimestamp();
    var range = try iterators.Range(u64).init(0, test_loops, 1);
    var iter = &range.iterator;
    while (iter.next()) |_| {
        try iterLoop();
    }
    const iterend = std.time.nanoTimestamp();
    try stdout.print("Iterator-style:   {}ns\n", .{(iterend - iterstart)});

    n = 0;
    const hackystart = std.time.nanoTimestamp();
    const Range = iterators.Range(u64);
    range = try Range.init(0, test_loops, 1);
    iter = &range.iterator;
    while (Range.next(iter)) |_| {
        try hackyFastLoop();
    }
    const hackyend = std.time.nanoTimestamp();
    try stdout.print("Hacky fast-style: {}ns\n", .{(hackyend - hackystart)});
}
