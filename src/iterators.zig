//! This module contains iterators for use in while loops, and some
//! functions that operate on them. Some iterators accept other
//! iterators.
//!
//! To use any iterator in this module, follow this pattern:
//! var specialized = IterType(args).init();
//! var iter = &specialized.iterator;
//! while (iter.next()) |v| {
//!     // Do things with v.
//! }
//!
//! Note that these iterators' next methods all change the state of the
//! iterators themselves. They can't be const and they shouldn't be
//! shared across threads.
const std = @import("std");

/// Iterator interface. Just passes calls straight on from next to
/// nextFn and from reset to resetFn.
pub fn Iterator(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Returns null when iterator is exhausted.
        nextFn: fn (self: *Self) ?T,

        /// Resets the iterator to its initial state.
        resetFn: fn (self: *Self) void,

        /// Returns null when iterator is exhausted.
        pub fn next(self: *Self) ?T {
            return self.nextFn(self);
        }

        /// Resets the iterator to its initial state.
        pub fn reset(self: *Self) void {
            return self.resetFn(self);
        }
    };
}

/// An iterator that repeats a single value, either forever or a
/// certain number of times.
pub fn Repeat(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Take the address of this to get a usable Iterator.
        iterator: Iterator(T),
        val: T,
        limit: ?struct { count: usize, sent: usize },

        /// Return the value, or null if finite and exhausted.
        pub fn next(iterator: *Iterator(T)) ?T {
            const self = @fieldParentPtr(Self, "iterator", iterator);
            if (self.limit) |limit| {
                if (limit.count == limit.sent) {
                    return null;
                }
                self.limit = .{ .count = limit.count, .sent = limit.sent + 1 };
            }
            return self.val;
        }

        /// Does nothing if the iterator is infinite. Otherwise resets
        /// the count.
        pub fn reset(iterator: *Iterator(T)) void {
            const self = @fieldParentPtr(Self, "iterator", iterator);
            if (self.limit) |limit| {
                self.limit = .{ .count = limit.count, .sent = 0 };
            }
        }

        /// val is the value repeated. If count is null, this iterator
        /// is infinete. Otherwise, it repeats count times.
        pub fn init(val: T, count: ?usize) Self {
            if (count) |cnt| {
                return Self{
                    .iterator = Iterator(T){
                        .nextFn = next,
                        .resetFn = reset,
                    },
                    .val = val,
                    .limit = .{ .count = cnt, .sent = 0 },
                };
            } else {
                return Self{
                    .iterator = Iterator(T){
                        .nextFn = next,
                        .resetFn = reset,
                    },
                    .val = val,
                    .limit = null,
                };
            }
        }
    };
}

/// Count unboundedly, starting at start by step. Note that this will
/// invoke safety-checked undefined behavior if T is allowed to overflow.
pub fn Count(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Take the address of this to get a usable Iterator.
        iterator: Iterator(T),
        next_val: T,
        start: T,
        step: T,

        /// This is an "infinite" counter, so it never returns
        /// null. It will, however, invoke safety-checked illegal
        /// behavior if T is allowed to overflow.
        pub fn next(iterator: *Iterator(T)) ?T {
            const self = @fieldParentPtr(Self, "iterator", iterator);
            const v = self.next_val;
            self.next_val += self.step;
            return v;
        }

        /// Start over at whatever the initial value of start was.
        pub fn reset(iterator: *Iterator(T)) void {
            const self = @fieldParentPtr(Self, "iterator", iterator);
            self.next_val = self.start;
        }

        /// Return an instance that starts with start and counts by step.
        /// For example, init(7, 3) would yield 7, 10, 13...
        pub fn init(start: T, step: T) Self {
            return Self{
                .iterator = Iterator(T){ .nextFn = next, .resetFn = reset },
                .next_val = start,
                .start = start,
                .step = step,
            };
        }
    };
}

/// Half-open range type. Call next() on its iterator to get values
/// out. Example usage:
///
/// var range = try Range(u32).init(0, 10, 1);
/// var iter = &range.iterator;
/// while (iter.next()) |n| {
///     std.debug.warn("{}\n", .{n});
/// }
pub fn Range(comptime T: type) type {
    // Some profiling results, as run on an i5-9600KF: This is
    // consistently a good deal slower than
    // u32 i = 0; while (i < limit) : (i += 1) {}
    // debug: 2.27 times the run time
    // release-fast, release-safe: 5 times the run time
    // release-small: 6 times the run time
    //
    // This is mostly due to the iterator construct. When calling
    // Range's next directly, the comparison becomes much more
    // favorable with all release modes running slightly faster
    // (around 0.1%) than the idiomatic while loop and Debug taking
    // about 7/4 as long.
    //
    // Note: when this was written (June 2020), passing
    // --single-threaded to a release-fast build slowed idiomatic
    // loops down by about a factor of 2. These benchmarks should
    // probably be re-run when the compiler is more stable.
    return struct {
        /// Take the address of this to get a usable Iterator.
        iterator: Iterator(T),
        next_val: T,
        start: T,
        step: T,
        end: T,
        const Self = @This();

        /// Return the next element in the range, or null if the last
        /// element in the range has already been returned.
        pub fn next(iterator: *Iterator(T)) ?T {
            const self = @fieldParentPtr(Self, "iterator", iterator);
            const rv = self.next_val;
            if (self.step < 0) {
                if (rv <= self.end) {
                    return null;
                }
            } else {
                if (rv >= self.end) {
                    return null;
                }
            }

            self.next_val += self.step;
            return rv;
        }

        /// Reset the range back to its start.
        pub fn reset(iterator: *Iterator(T)) void {
            const self = @fieldParentPtr(Self, "iterator", iterator);
            self.next_val = self.start;
        }

        /// Initialize. Returns error if step size is invalid.  Range
        /// runs from start (inclusive) to end (exclusive),
        /// incrementing by step. So init(2, 7, 3) would yield 2, then
        /// 5, then null.
        pub fn init(start: T, end: T, step: T) !Self {
            if (step == 0) {
                return error.ZeroStepSize;
            }
            return Self{
                .next_val = start,
                .start = start,
                .end = end,
                .step = step,
                .iterator = Iterator(T){
                    .nextFn = next,
                    .resetFn = reset,
                },
            };
        }
    };
}

/// Reverse a slice. Example usage:
///
/// const word: []const u8 = "Word";
/// var drow = Reversed(u8).init(word);
/// var iter = &drow.iterator;
/// while (drow.next()) |c| {
///     std.debug.warn("{}", .{c});
/// std.debug.warn("\n", .{});
pub fn Reversed(comptime T: type) type {
    return struct {
        const Self = @This();
        idx: ?usize,
        slice: []const T,

        /// Initialize with slice to be reversed.
        pub fn init(slice: []const T) Self {
            return Self{ .idx = slice.len - 1, .slice = slice };
        }

        /// Reset the iterator state to what it was when initialized.
        pub fn reset(self: *Self) void {
            self.idx = self.slice.len - 1;
        }

        /// Return the previous element in the slice, or null if the whole
        /// slice has been consumed.
        pub fn next(self: *Self) ?T {
            var rv: T = undefined;
            if (self.idx) |i| {
                if (i == 0) {
                    defer self.idx = null;
                } else {
                    defer self.idx = self.idx.? - 1;
                }
                return self.slice[i];
            } else {
                return null;
            }
        }
    };
}

/// Convert a slice of T to an iterator that can be used with the
/// other iterators in this module.
pub fn SliceIter(comptime T: type) type {
    return struct {
        const Self = @This();
        idx: ?usize,
        slice: []const T,
        iterator: Iterator(T),

        /// Initialize with a slice.
        pub fn init(slice: []const T) Self {
            return Self{
                .idx = 0,
                .slice = slice,
                .iterator = Iterator(T){
                    .nextFn = next,
                    .resetFn = reset,
                },
            };
        }

        /// Reset the iterator to the start.
        pub fn reset(iterator: *Iterator(T)) void {
            const self = @fieldParentPtr(Self, "iterator", iterator);
            self.idx = 0;
        }

        /// Return the next element in the slice, or null if the whole
        /// slice has been consumed.
        pub fn next(iterator: *Iterator(T)) ?T {
            const self = @fieldParentPtr(Self, "iterator", iterator);
            if (self.idx) |i| {
                if (i < self.slice.len) {
                    self.idx = i + 1;
                    return self.slice[i];
                } else {
                    self.idx = null;
                    return null;
                }
            } else {
                return null;
            }
        }
    };
}

/// Get the cartesian product of iterators. All iterators' next
/// methods must return the same type, passed in as T. The number of
/// iterators to process is passed as num.
///
/// Sample usage:
/// var a = try Range(u32).init(0, 2, 1);
/// var b = try Range(u32).init(4, 8, 2);
/// var iterators = [_]*Iterator(u32){ &a.iterator, &b.iterator };
/// var product = Product(u32, 2).init(iterators);
/// var iter = &product.iterator;
/// while (iter.next()) |vals| {
///     // vals will have these values: {0, 4}, {1, 4}, {0, 6}, {1, 6}
/// }
pub fn Product(comptime T: type, comptime num: usize) type {
    return struct {
        const Self = @This();
        // This would be better as a tuple. Note for when we get tuple
        // types. Then the iterators being multiplied don't need to
        // all return the same type.
        const Result = [num]T;

        /// Take the address of this to get a usable Iterator.
        iterator: Iterator(Result),
        children: [num]*Iterator(T),
        next: [num]T,
        done: bool = false,

        /// Return the next array of combinations, or null if the last
        /// one has been returned.
        pub fn next(iterator: *Iterator(Result)) ?Result {
            const self = @fieldParentPtr(Self, "iterator", iterator);
            if (self.done)
                return null;
            const prev: Result = self.next;
            for (self.children) |child, idx| {
                if (child.next()) |val| {
                    self.next[idx] = val;
                    self.done = false;
                    break;
                } else {
                    child.reset();
                    self.next[idx] = child.next().?;
                }
            } else {
                self.done = true;
            }
            return prev;
        }

        /// Start over from the beginning.
        pub fn reset(iterator: *Iterator(Result)) void {
            const self = @fieldParentPtr(Self, "iterator", iterator);
            for (self.children) |child| {
                child.reset();
            }
        }

        /// Initialize and return structure. args is an array of
        /// iterators to combine. Invokes safety-checked illegal
        /// behavior if any iterators in args are empty.
        pub fn init(args: [num]*Iterator(T)) Self {
            var rv = Self{
                .iterator = Iterator(Result){
                    .nextFn = next,
                    .resetFn = reset,
                },
                .children = args,
                .next = undefined,
            };

            for (args) |iter, idx| {
                rv.next[idx] = iter.next().?;
            }
            return rv;
        }
    };
}

/// Apply fun to successive elements in iter. Initial value of acc is
/// init.
pub fn fold(
    comptime T: type,
    fun: fn (acc: T, val: T) T,
    iter: *Iterator(T),
    init: T,
) T {
    var accumulator: T = init;
    while (iter.next()) |val| {
        accumulator = fun(accumulator, val);
    }
    return accumulator;
}

/// Don't use this. It's broken.
pub fn ffold(
    comptime T: type,
    fun: fn (acc: T, val: T) T,
    iter: *Iterator(T),
    init: T,
) T {
    if (iter.next()) |val| {
        return @call(
            .{ .modifier = .always_tail },
            ffold,
            .{ T, fun, iter, val },
        );
    } else {
        return init;
    }
}

const testing = std.testing;
test "range ascend" {
    var range = try Range(u32).init(0, 10, 1);
    var iter = &range.iterator;
    var correct: u32 = 0;
    while (iter.next()) |n| {
        testing.expectEqual(correct, n);
        correct += 1;
    }
    testing.expectEqual(correct, 10);
    testing.expectEqual(iter.next(), null);
}

test "range descend" {
    var range = try Range(i32).init(10, 0, -1);
    var iter = &range.iterator;
    var correct: i32 = 10;
    while (iter.next()) |n| {
        testing.expectEqual(correct, n);
        correct -= 1;
    }
    testing.expectEqual(correct, 0);
    testing.expectEqual(iter.next(), null);
}

test "range skip" {
    var range = try Range(u32).init(0, 10, 2);
    var iter = &range.iterator;
    var correct: u32 = 0;
    while (iter.next()) |n| {
        testing.expectEqual(correct, n);
        correct += 2;
    }
    testing.expectEqual(correct, 10);
    testing.expectEqual(iter.next(), null);
}

test "range runtime" {
    var start: u32 = 0;
    while (start < 10) : (start += 1) {
        var range = try Range(u32).init(start, 10, 1);
        var iter = &range.iterator;
        var correct: u32 = start;
        while (iter.next()) |n| {
            testing.expectEqual(correct, n);

            correct += 1;
        }
        testing.expectEqual(correct, 10);
        testing.expectEqual(iter.next(), null);
    }
}

test "reverse" {
    const word: []const u8 = "This is some text.";
    var backwards = Reversed(u8).init(word);
    var idx: isize = word.len - 1;
    while (backwards.next()) |letter| {
        testing.expectEqual(word[@intCast(usize, idx)], letter);
        idx -= 1;
    }
    testing.expectEqual(idx, -1);
}

test "product" {
    const R = Range(u32);
    var a = try R.init(0, 10, 1);
    var b = try R.init(10, 25, 1);
    var iterators = [_]*Iterator(u32){ &a.iterator, &b.iterator };
    var product = Product(u32, 2).init(iterators);

    var pi = &product.iterator;

    var correct_a: u32 = 0;
    var correct_b: u32 = 10;
    while (pi.next()) |ab| {
        testing.expectEqual(ab[0], correct_a);
        testing.expectEqual(ab[1], correct_b);
        correct_a += 1;
        if (correct_a == 10) {
            correct_a = 0;
            correct_b += 1;
        }
    }
    testing.expectEqual(correct_b, 25);
    testing.expectEqual(pi.next(), null);
}

test "count" {
    var count = Count(u64).init(0, 3);
    var iter = &count.iterator;
    var correct: u64 = 0;
    while (iter.next()) |c| {
        testing.expectEqual(correct, c);
        correct += 3;
        if (correct > 150) break;
    }
    testing.expectEqual(correct, 153);
}

test "repeat" {
    var repeat = Repeat(u64).init(8, 100);
    var iter = &repeat.iterator;
    var count: u64 = 0;
    while (iter.next()) |eight| {
        testing.expectEqual(eight, 8);
        count += 1;
    }
    testing.expectEqual(count, 100);

    repeat = Repeat(u64).init(7, null);
    iter = &repeat.iterator;
    count = 0;
    while (iter.next()) |seven| {
        testing.expectEqual(seven, 7);
        count += 1;
        if (count == 1000) break;
    }
    testing.expectEqual(count, 1000);
}

fn add(a: u32, b: u32) u32 {
    return a + b;
}

test "fold over range" {
    var range = try Range(u32).init(1, 10, 1);
    var iter = &range.iterator;
    const total = fold(u32, add, iter, 12);
    testing.expectEqual(total, 12 + 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9);
}

test "SliceIter" {
    const slice: []const u8 = "Text";
    var slice_iter = SliceIter(u8).init(slice);
    var iter = &slice_iter.iterator;
    var idx: usize = 0;
    while (iter.next()) |c| {
        testing.expectEqual(c, slice[idx]);
        idx += 1;
    }
    testing.expectEqual(idx, slice.len);
}
