const std = @import("std");

/// A minimal TSL interpreter.
///
/// Each interpreter shares an `Allocator`, knows its optional `parent`,
/// has `bindings` for `Value`s and can run a slice of `words` using the
/// `run` method. Bind Zig implementations to words by calling `cmd`.
/// Access values using `get` and `put`. Evaluate the next word with
/// `eval` and all words by calling `evalAll`. Use `run` to evaluate
/// a new slice of words.
pub const Tsl = struct {
    pub const Error = error{
        EndOfInput,
        BlockExpected,
        UnknownWord,
        OutOfMemory,
    };

    pub const Value = union(enum) {
        int: i64,
        builtin: *const fn (*Tsl) Error!i64,
        function: struct {
            params: []const []const u8,
            body: []const []const u8,
        },
    };

    allocator: std.mem.Allocator,
    parent: ?*Tsl,
    bindings: std.StringHashMap(Value),
    words: []const []const u8 = &[_][]const u8{},
    index: usize = 0,

    pub fn init(parent: ?*Tsl, allocator: std.mem.Allocator) Tsl {
        return Tsl{
            .allocator = allocator,
            .parent = parent,
            .bindings = std.StringHashMap(Value).init(allocator),
        };
    }

    pub fn deinit(self: *Tsl) void {
        self.bindings.deinit();
    }

    /// Returns the value bound to `name` or `null`.
    pub fn get(self: *Tsl, name: []const u8) ?Value {
        if (self.bindings.get(name)) |value| return value;
        if (self.parent) |parent| return parent.get(name);
        return null;
    }

    /// Binds `value` to `name`.
    pub fn put(self: *Tsl, name: []const u8, value: Value) Error!void {
        self.bindings.put(name, value) catch return Error.OutOfMemory;
    }

    /// Returns the next word or the error `EndOfInput`.
    fn next(self: *Tsl) Error![]const u8 {
        if (self.index == self.words.len) return Error.EndOfInput;
        const word = self.words[self.index];
        self.index += 1;
        return word;
    }

    /// Returns the next block (after the initial `[`).
    fn block(self: *Tsl) Error![]const []const u8 {
        const start = self.index;
        var count: usize = 1;
        while (count > 0) {
            const word = try self.next();
            if (word[0] == '[') count += 1;
            if (word[0] == ']') count -= 1;
        }
        return self.words[start .. self.index - 1];
    }

    /// Returns the contents of the next block, unevaluated.
    /// (A workaround for not being able to evaluate blocks)
    fn nextBlock(self: *Tsl) Error![]const []const u8 {
        const word = try self.next();
        if (word[0] != '[') return Error.BlockExpected;
        return self.block();
    }

    /// Evaluates and returns the next word.
    fn eval(self: *Tsl) Error!i64 {
        const word = try self.next();
        if (self.get(word)) |value| {
            return switch (value) {
                .int => value.int,
                .builtin => value.builtin(self),
                .function => {
                    var tsl = Tsl.init(self, self.allocator);
                    defer tsl.deinit();
                    for (value.function.params) |param| {
                        var arg = Value{ .int = try self.eval() };
                        try tsl.bindings.put(param, arg);
                    }
                    return tsl.run(value.function.body);
                },
            };
        }
        return std.fmt.parseInt(i64, word, 10) catch Error.UnknownWord;
    }

    /// Evaluates all remaining words and returns the last result.
    fn evalAll(self: *Tsl) Error!i64 {
        var result: i64 = 0;
        while (self.index < self.words.len) {
            result = try self.eval();
        }
        return result;
    }

    /// Evaluates `words` using `evalAll`.
    fn run(self: *Tsl, words: []const []const u8) Error!i64 {
        var tsl = Tsl{
            .allocator = self.allocator,
            .parent = self,
            .bindings = self.bindings,
            .words = words,
        };
        return tsl.evalAll();
    }

    /// Evaluates `input` using `run`.
    fn runString(self: *Tsl, input: []const u8) Error!i64 {
        const L = struct {
            fn isWhitespace(c: u8) bool {
                return std.ascii.isWhitespace(c);
            }
            fn isSyntax(c: u8) bool {
                return c == '[' or c == ']';
            }
        };

        var words = std.ArrayList([]const u8).init(self.allocator);
        defer words.deinit();

        const len = input.len;
        var index: usize = 0;
        while (true) {
            while (index < len and L.isWhitespace(input[index])) {
                index += 1;
            }
            if (index == len) break;
            const start = index;
            if (L.isSyntax(input[index])) {
                index += 1;
            } else {
                while (index < len and !L.isWhitespace(input[index]) and !L.isSyntax(input[index])) {
                    index += 1;
                }
            }
            try words.append(input[start..index]);
        }

        return self.run(words.items);
    }

    /// Adds `builtin` as an implementation for `name`.
    fn cmd(self: *Tsl, name: []const u8, builtin: *const fn (*Tsl) Error!i64) !void {
        try self.put(name, Value{ .builtin = builtin });
    }
};

// nicely grouped mainly for collapsing it in the IDE
const Builtins = struct {
    fn doPrint(self: *Tsl) Tsl.Error!i64 {
        std.debug.print("> {d}\n", .{try self.eval()});
        return 0;
    }

    fn doAdd(self: *Tsl) Tsl.Error!i64 {
        return try self.eval() + try self.eval();
    }

    fn doSub(self: *Tsl) Tsl.Error!i64 {
        return try self.eval() - try self.eval();
    }

    fn doMul(self: *Tsl) Tsl.Error!i64 {
        return try self.eval() * try self.eval();
    }

    fn doDiv(self: *Tsl) Tsl.Error!i64 {
        return @divExact(try self.eval(), try self.eval());
    }

    fn doEq(self: *Tsl) Tsl.Error!i64 {
        return if (try self.eval() == try self.eval()) 1 else 0;
    }

    fn doIf(self: *Tsl) Tsl.Error!i64 {
        const cond = try self.eval();
        const thenB = try self.nextBlock();
        const elseB = try self.nextBlock();
        return self.run(if (cond != 0) thenB else elseB);
    }

    fn doFunc(self: *Tsl) Tsl.Error!i64 {
        const name = try self.next();
        const params = try self.nextBlock();
        const body = try self.nextBlock();
        try self.put(name, Tsl.Value{ .function = .{
            .params = params,
            .body = body,
        } });
        return 0;
    }

    fn setup(tsl: *Tsl) !void {
        try tsl.cmd("drucke", doPrint);
        try tsl.cmd("addiere", doAdd);
        try tsl.cmd("subtrahiere", doSub);
        try tsl.cmd("multipliziere", doMul);
        try tsl.cmd("dividiere", doDiv);
        try tsl.cmd("gleich?", doEq);
        try tsl.cmd("wenn", doIf);
        try tsl.cmd("funktion", doFunc);
    }
};

pub fn main() !void {
    var a = std.heap.page_allocator;
    var tsl = Tsl.init(null, a);
    try Builtins.setup(&tsl);
    _ = try tsl.run(&[_][]const u8{
        "funktion",
        "a",
        "[",
        "]",
        "[",
        "42",
        "]",
        "drucke",
        "a",
    });
    _ = try tsl.runString(
        \\ funktion fakultät [n] [
        \\   wenn gleich? n 0 [1] [
        \\     multipliziere fakultät subtrahiere n 1 n
        \\   ]
        \\ ]
        \\ drucke fakultät 20
    );
}
