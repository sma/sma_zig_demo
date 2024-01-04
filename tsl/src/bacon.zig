//! A reference counting memory management with cycle detection by David Bacon
//!
//! **DOES NOT WORK**
//!
//! The algorithm:
//!
//! Increment(S)
//!     RC(S) += 1
//!     color(S) = black
//!
//! Decrement(S)
//!     RC(S) -= 1
//!     if (RC(S) == 0)
//!         Release(S)
//!     else
//!         PossibleRoot(S)
//!
//! Release(S)
//!     for T in children(S)
//!         Decrement(T)
//!     color(S) = black
//!     if (!buffered(S))
//!         Free(S)
//!
//! PossibleRoot(S)
//!     if (color(S) != purple)
//!         color(S) = purple
//!         if (!buffered(S))
//!             buffered(S) = true
//!             append S to Roots
//!
//! CollectCycles()
//!     MarkRoots()
//!     ScanRoots()
//!     CollectRoots()
//!
//! MarkRoots()
//!     for S in Roots
//!         if (color(S) == purple)
//!             MarkGray(S)
//!         else
//!             buffered(S) = false
//!             remove S from Roots
//!             if (color(S) == black and RC(S) == 0)
//!                 Free(S)
//!
//! ScanRoots()
//!     for S in Roots
//!         Scan(S)
//!
//! CollectRoots()
//!     for S in Roots
//!         remove S from Roots
//!         buffered(S) = false
//!         CollectWhite(S)
//!
//! MarkGray(S)
//!     if (color(S) != gray)
//!         color(S) = gray
//!         for T in children(S)
//!             RC(T) -= 1
//!             MarkGray(T)
//!
//! Scan(S)
//!     if (color(S) == gray)
//!         if (RC(S) > 0)
//!             ScanBlack(S)
//!         else
//!             color(S) = white
//!             for T in children(S)
//!                 Scan(S)
//!
//! ScanBlack(S)
//!     color(S) = black
//!     for T in children(S)
//!         RC(T) += 1
//!         if (color(T) != black)
//!             ScanBlack(S)
//!
//! CollectWhite(S)
//!     if (color(S) == white and !buffered(S))
//!         color(S) = black
//!         for T in children(S)
//!             CollectWhite(T)
//!         Free(S)
//!

const std = @import("std");

// `T` must have an `init` function and a `deinit` method
// and a `rcDependencies` method which returns an iterator
// with a `next` method that returns a `?Rc(T)`.
fn Rc(comptime T: type) type {
    const Color = enum(u2) {
        /// in use or free
        black,
        /// possible root of cycle
        purple,
        /// possible member of cycle
        gray,
        // member of garbage collect
        white,
    };

    const Buffered = enum(u1) { yes, no };

    const n = 1024;

    return struct {
        count: i29, // hoping that count||color||buffered = 32 bit
        color: Color,
        buffered: Buffered,
        object: T,

        const Self = @This();

        var buffer: [n]*Rc(T) = undefined;
        var index: usize = 0;

        /// Allocates a new `T` by calling `init(std.mem.Allocator)`.
        fn new(a: std.mem.Allocator) Self {
            return .{
                .count = 1,
                .color = .black,
                .buffered = .no,
                .object = T.init(a),
            };
        }

        /// Uses the `object`, also returning it.
        fn use(rc: *Self) T {
            return rc.inc().object;
        }

        fn inc(rc: *Self) *Self {
            rc.count += 1;
            rc.color = .black;
            return rc;
        }

        /// Marks the object as unused, possibly releasing it.
        /// This might call `collectCycles`.
        fn unuse(rc: *Self) void { // decrement
            std.debug.assert(rc.count > 0);
            rc.count -= 1;
            if (rc.count == 0) {
                rc.release();
            } else {
                // possibleRoot
                if (rc.color == .purple) return;
                rc.color = .purple;
                if (rc.buffered == .yes) return;
                rc.buffered = .yes;
                buffer[index] = rc;
                index += 1;
                if (index == buffer.len) {
                    collectCycles();
                    if (index == buffer.len) {
                        @panic("buffer full");
                    }
                }
            }
        }

        /// Frees all resources, either now or later.
        fn release(rc: *Self) void {
            var i = rc.object.rcDependencies();
            while (i.next()) |t| {
                t.unuse();
            }
            rc.color = .black;
            if (rc.buffered == .no) {
                rc.object.deinit();
            }
        }

        /// Performs a cycle detection.
        fn collectCycles() void {
            markRoots();
            scanRoots();
            collectRoots();
        }

        // 1st pass: iterate all possible roots and mark then "gray";
        // Also free resources of unused objects still stuck in buffer
        fn markRoots() void {
            var i: usize = 0;
            while (i < index) : (i += 1) {
                const rc = buffer[i];
                if (rc.color == .purple) {
                    rc.markGray();
                } else {
                    rc.buffered = .no;
                    index -= 1;
                    if (i < index) buffer[i] = buffer[index];
                    if (rc.color == .black and rc.count == 0) {
                        rc.object.deinit();
                    }
                }
            }
        }

        // 2nd pass:
        fn scanRoots() void {
            var i: usize = 0;
            while (i < index) : (i += 1) {
                buffer[i].scan();
            }
        }

        // 3rd pass:
        fn collectRoots() void {
            var i: usize = 0;
            while (i < index) : (i += 1) {
                const rc = buffer[i];
                rc.buffered = .no;
                rc.collectWhite();
                index -= 1;
                if (i < index) buffer[i] = buffer[index];
            }
        }

        /// Traces receiver and all dependencies.
        fn markGray(rc: *Self) void {
            if (rc.color == .gray) return;
            rc.color = .gray;
            var i = rc.object.rcDependencies();
            while (i.next()) |d| {
                d.count -= 1;
                d.markGray();
            }
        }

        fn scan(rc: *Self) void {
            if (rc.color != .gray) return;
            if (rc.count > 0) {
                rc.scanBlack();
            } else {
                rc.color = .white;
                var i = rc.object.rcDependencies();
                while (i.next()) |t| {
                    t.scan();
                }
            }
        }

        fn scanBlack(rc: *Self) void {
            rc.color = .black;
            var i = rc.object.rcDependencies();
            while (i.next()) |t| {
                t.count += 1;
                if (t.color != .black) t.scanBlack();
            }
        }

        fn collectWhite(rc: *Self) void {
            if (rc.color == .white and rc.buffered == .no) {
                rc.color = .black;
                var i = rc.object.rcDependencies();
                while (i.next()) |t| {
                    t.collectWhite();
                }
                rc.object.deinit();
            }
        }
    };
}

const State = struct {
    const Value = union(enum) {
        int: i64,
        state: *Rc(State),
    };

    bindings: std.StringHashMap(Value),

    fn init(a: std.mem.Allocator) State {
        return .{ .bindings = std.StringHashMap(Value).init(a) };
    }

    fn deinit(s: *State) void {
        var i = s.bindings.valueIterator();
        while (i.next()) |v| {
            switch (v.*) {
                .state => v.state.unuse(),
                else => {},
            }
        }
        s.bindings.deinit();
        std.debug.print("deinit\n", .{});
    }

    const RcStateIterator = struct {
        iterator: std.StringHashMap(Value).ValueIterator,

        fn next(self: *RcStateIterator) ?*Rc(State) {
            if (self.iterator.next()) |value| {
                switch (value.*) {
                    .int => return self.next(),
                    .state => return value.state,
                }
            }
            return null;
        }
    };

    fn rcDependencies(s: *State) RcStateIterator {
        return .{ .iterator = s.bindings.valueIterator() };
    }
};

pub fn main() !void {
    const a = std.heap.page_allocator;
    var state1 = Rc(State).new(a);
    var state2 = Rc(State).new(a);
    try state1.object.bindings.put("x", State.Value{ .state = state2.inc() });
    defer state1.unuse();
    // defer state2.unuse();
}
