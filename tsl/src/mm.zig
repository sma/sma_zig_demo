const std = @import("std");

/// Represents a TSL value.
///
/// This is a 48-byte value type because of `closure` and we should probably
/// use a pointer here. This however means we need to allocate and free memory
/// when creating and destroying `State` instances.
///
/// The `free` variant is used to implement a linked list of free `Value` used
/// by the memory manager. That memory manager also needs to "mark" values.
pub const Value = union(enum) {
    nil,
    int: i64, // 8 bytes
    string: []const u8, // 16 bytes
    block: []const []const u8, // 16 bytes
    builtin: *const fn (*const State) Value, // 8 bytes
    closure: struct { // 40 bytes
        parent: *const State,
        params: []const []const u8,
        block: []const []const u8,
    },
    free: *Value, // 8 bytes
};

/// Holds the state of the TSL interpreter.
const State = struct {
    parent: ?*const State,
    bindings: std.StringHashMap(Value),
    words: [][]const u8,
    index: usize,

    /// Creates a new state with the given `parent`.
    fn init(parent: ?*const State, allocator: std.mem.Allocator) *const State {
        return &State{
            .parent = parent,
            .bindings = std.StringHashMap(Value).init(allocator),
            .words = &[_][]const u8{},
            .index = 0,
        };
    }

    /// Frees all reserved memory.
    fn deinit(state: *State) void {
        // var it = state.bindings.iterator();
        // while (it.next()) |entry| {
        //     switch (entry.value.*) {
        //         .closure => entry.value.deinit(),
        //         else => {},
        //     }
        // }
        state.parent = null;
        state.bindings.deinit();
        state.words = &[_][]const u8{};
        state.index = 0;
    }

    /// Returns the value bound to `name`.
    fn get(state: *State, name: []const u8) ?Value {
        var current: ?*State = state;
        while (current != null) : (current = current.parent) {
            if (current.locals.get(name)) |value| {
                return value;
            }
        }
        return state.globals.get(name);
    }

    /// Binds `value` to `name`. This overwrites any existing binding.
    /// If no binding exists, it is created in the local scope.
    fn put(state: *State, name: []const u8, value: Value) !void {
        var current: ?*State = state;
        while (current != null) : (current = current.parent) {
            if (current.locals.get(name)) {
                try current.locals.put(name, value);
                return;
            }
        }
        if (state.globals.get(name)) {
            try state.globals.put(name, value);
            return;
        }
        try state.locals.put(name, value);
    }
};

/// An automatic memory manager for states.
pub const MM = struct {
    const ManagedState = struct {
        state: State,
        used: bool,
        marked: bool,
    };

    states: []ManagedState,
    allocator: std.mem.Allocator,

    /// Allocates memory for `n` states.
    pub fn init(n: usize, allocator: std.mem.Allocator) !MM {
        return MM{
            .states = try allocator.alloc(ManagedState, n),
            .allocator = allocator,
        };
    }

    /// Frees all reserved memory.
    pub fn deinit(mm: *MM) void {
        for (mm.states) |state| {
            if (state.used) {
                state.state.bindings.deinit();
            }
        }
        mm.allocator.free(mm.states);
    }

    /// Returns a new empty state with a preallocated bindings hashmap.
    pub fn alloc(mm: *MM) !*State {
        return mm._alloc() catch {
            // assume that the first state is always alive
            if (mm.states.len > 0 and mm.states[0].used) {
                mm.gc(&[_]*State{&mm.states[0].state});
            }
            return mm._alloc();
        };
    }

    fn _alloc(mm: *MM) !*State {
        for (0..mm.states.len) |i| {
            var st = &mm.states[i];
            if (!st.used) {
                st.used = true;
                st.state.parent = null;
                st.state.bindings = std.StringHashMap(Value).init(mm.allocator);
                st.state.words = &[_][]const u8{};
                st.state.index = 0;
                return &st.state;
            }
        }
        // we could try to allocate more memory here
        return error.OutOfMemory;
    }

    /// Converts `state` pointer to a `states` array index.
    fn index(mm: *MM, state: *const State) ?usize {
        const ptr = @intFromPtr(state);
        const siz = @sizeOf([2]ManagedState) / 2;
        const i = (ptr - @intFromPtr(&mm.states[0])) / siz;
        return if (i >= 0 and i < mm.states.len) i else null;
    }

    /// Marks the given `state` as still alive. Searches all bindings for
    /// states to mark them, too. Then continues with the parent state.
    fn mark(mm: *MM, state: *const State) void {
        // make sure, state is a valid pointer
        const ptr = @intFromPtr(state);
        const siz = @sizeOf([2]ManagedState) / 2;
        const ofs = ptr - @intFromPtr(&mm.states[0]);
        std.debug.assert(ofs >= 0 and ofs < mm.states.len * siz and ofs % siz == 0);

        // then use as a managed state
        const managedState = @as(*ManagedState, @ptrFromInt(ptr));

        // it must be used, otherwise we've a dangling pointer
        std.debug.assert(managedState.used);

        // if already marked, we are done
        if (managedState.marked) {
            return;
        }
        managedState.marked = true;

        // search bindings for states to mark them, too
        var it = state.bindings.iterator();
        while (it.next()) |entry| {
            switch (entry.value_ptr.*) {
                .closure => |closure| mm.mark(closure.parent),
                else => {},
            }
        }

        // continue with parent
        if (state.parent) |parent| {
            mm.mark(parent);
        }
    }

    /// Frees all unused states.
    fn sweep(mm: *MM) void {
        for (0..mm.states.len) |i| {
            var state = &mm.states[i];
            if (state.used) {
                if (state.marked) {
                    std.debug.print("keep {x}\n", .{@intFromPtr(state)});
                    state.marked = false;
                } else {
                    std.debug.print("free {x}\n", .{@intFromPtr(state)});
                    state.state.bindings.deinit();
                    state.used = false;
                }
            }
        }
    }

    fn gc(mm: *MM, roots: []const *State) void {
        for (roots) |state| mm.mark(state);
        mm.sweep();
    }

    /// Prints the number of used states.
    fn count(mm: *MM) void {
        var used: usize = 0;
        for (mm.states) |state| {
            if (state.used) {
                used += 1;
            }
        }
        std.debug.print("used: {}\n", .{used});
    }
};

pub fn main() !void {
    var allocator = std.heap.page_allocator;
    var mm = try MM.init(100, allocator);
    var state1 = try mm.alloc();
    var state2 = try mm.alloc();
    _ = try mm.alloc();
    try state2.bindings.put("x", try Value.closure(
        state1,
        &[_][]const u8{},
        &[_][]const u8{},
        allocator,
    ));
    mm.count();
    mm.gc(&[_]*State{state2});
    mm.count();
}
