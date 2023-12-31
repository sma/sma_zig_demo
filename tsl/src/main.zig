const std = @import("std");

pub const Reader = struct {
    input: []const u8,
    index: usize = 0,

    fn isOneOf(c: u8, s: []const u8) bool {
        return for (s) |other| {
            if (c == other) break true;
        } else false;
    }

    fn isWhitespace(c: u8) bool {
        return isOneOf(c, " \n\r\t");
    }

    fn isParentheses(c: u8) bool {
        return isOneOf(c, "[]{}();");
    }

    fn isWord(c: u8) bool {
        return !isWhitespace(c) and !isParentheses(c);
    }

    pub fn nextWord(self: *Reader) []const u8 {
        while (self.index < self.input.len and isWhitespace(self.input[self.index])) {
            self.index += 1;
        }
        if (self.index == self.input.len)
            return self.input[self.index..self.index];
        const start = self.index;
        if (self.input[self.index] == ';') {
            self.index += 1;
            while (self.index < self.input.len and self.input[self.index] != '\n') {
                self.index += 1;
            }
        } else if (self.input[self.index] == '"') {
            self.index += 1;
            while (self.index < self.input.len and self.input[self.index] != '"') {
                self.index += 1;
            }
            if (self.index < self.input.len) {
                self.index += 1;
            }
        } else if (isParentheses(self.input[self.index])) {
            self.index += 1;
            return self.input[start..self.index];
        } else {
            self.index += 1;
            while (self.index < self.input.len and isWord(self.input[self.index])) {
                self.index += 1;
            }
        }
        return self.input[start..self.index];
    }
};

test "Reader" {
    var r = Reader{ .input = "[3 \"[]\" drucke]" };
    var word = r.nextWord();
    try std.testing.expectEqualStrings(word, "[");
    word = r.nextWord();
    try std.testing.expectEqualStrings(word, "3");
    word = r.nextWord();
    try std.testing.expectEqualStrings(word, "\"[]\"");
    word = r.nextWord();
    try std.testing.expectEqualStrings(word, "drucke");
    word = r.nextWord();
    try std.testing.expectEqualStrings(word, "]");
    word = r.nextWord();
    try std.testing.expectEqualStrings(word, "");
}

/// Splits the `input` into words.
///
/// The caller must eventually free the returned slice.
fn split(input: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
    var words = std.ArrayList([]const u8).init(allocator);
    defer words.deinit();

    var reader = Reader{ .input = input };
    while (true) {
        const word = reader.nextWord();
        if (word.len == 0) break;
        try words.append(word);
    }
    return words.toOwnedSlice();
}

test "split" {
    var allocator = std.testing.allocator;
    var words = try split("drucke addiere 3 addiere 4 5", allocator);
    try std.testing.expectEqualStrings(words[0], "drucke");
    try std.testing.expectEqualStrings(words[1], "addiere");
    try std.testing.expectEqualStrings(words[2], "3");
    try std.testing.expectEqualStrings(words[3], "addiere");
    try std.testing.expectEqualStrings(words[4], "4");
    try std.testing.expectEqualStrings(words[5], "5");
    allocator.free(words);
}

pub const Tsl = struct {
    const Error = error{
        UnbalancedBlock,
        BlockExpected,
        EndOfInput,
        UnknownWord,
        OutOfMemory,
    };

    const Value = union(enum) {
        int: i64,
        builtin: *const fn (*Tsl) Tsl.Error!i64,
        function: struct {
            tsl: *Tsl,
            params: [][]const u8,
            body: [][]const u8,
        },
    };

    allocator: std.mem.Allocator,
    bindings: std.StringHashMap(Value),
    parent: ?*Tsl,
    words: [][]const u8,
    index: usize = 0,

    pub fn init(parent: ?*Tsl, allocator: std.mem.Allocator) !Tsl {
        return Tsl{
            .allocator = allocator,
            .bindings = std.StringHashMap(Value).init(allocator),
            .parent = parent,
            .words = &[_][]const u8{},
        };
    }

    fn deinit(self: *Tsl) void {
        self.bindings.deinit();
    }

    /// Returns the next word or `Error.EndOfInput`.
    pub fn next(self: *Tsl) ![]const u8 {
        if (self.index == self.words.len) {
            return Error.EndOfInput;
        }
        const word = self.words[self.index];
        self.index += 1;
        return word;
    }

    /// Returns the next block (after already reading the `[`)
    /// as a new `Tsl` instance or `Error.UnbalancedBlock` if
    /// a matching `]` is missing.
    pub fn block(self: *Tsl) Error!Tsl {
        const start = self.index;
        var count: usize = 1;
        while (count > 0) {
            const word = self.next() catch {
                return Error.UnbalancedBlock;
            };
            if (word[0] == '[') {
                count += 1;
            } else if (word[0] == ']') {
                count -= 1;
            }
        }
        return Tsl{
            .allocator = self.allocator,
            .bindings = self.bindings,
            .parent = self.parent,
            .words = self.words[start .. self.index - 1],
        };
    }

    /// Returns the value bound to `name` or `Error.UnknownWord`.
    pub fn find(self: *Tsl, name: []const u8) Error!Value {
        if (self.bindings.get(name)) |impl| return impl;
        if (self.parent) |parent| return parent.find(name);
        return Error.UnknownWord;
    }

    /// Binds `name` to `value`.
    pub fn set(self: *Tsl, name: []const u8, value: Value) Error!void {
        try self.bindings.put(name, value);
    }

    /// Returns the result of the evaluation of the next word.
    pub fn eval(self: *Tsl) Error!i64 {
        const word = try self.next();
        const impl = self.find(word) catch {
            return std.fmt.parseInt(i64, word, 10) catch {
                std.debug.print("unknown word: {s}\n", .{word});
                return Error.UnknownWord;
            };
        };
        switch (impl) {
            Value.int => return impl.int,
            Value.builtin => return try impl.builtin(self),
            Value.function => {
                const t = impl.function.tsl;
                var tt = try Tsl.init(t, t.allocator);
                defer tt.deinit();
                tt.words = impl.function.body;
                for (impl.function.params) |param| {
                    var value = Value{ .int = try self.eval() };
                    try tt.bindings.put(param, value);
                }
                return tt.evalAll();
            },
        }
    }

    /// Returns the result of the evaluation of all words until
    /// the end of the input. Without any words, this returns 0.
    pub fn evalAll(self: *Tsl) Error!i64 {
        var result: i64 = 0;
        while (self.index < self.words.len) {
            result = try self.eval();
        }
        return result;
    }

    /// Runs the given words like `evalAll`.
    pub fn run(self: *Tsl, input: []const u8) Error!i64 {
        self.words = try split(input, self.allocator);
        defer self.allocator.free(self.words);
        self.index = 0;
        return self.evalAll();
    }

    /// Returns a block as `Tsl` instance or `Error.BlockExpected`
    /// if the next word isn't a `[`. Actually, this shouldn't be
    /// necessary, as I'd like to bind `[` to a builtin function
    /// and allow blocks as well as integers as valid values.
    fn mustBeBlock(self: *Tsl) Error!Tsl {
        var word = self.next() catch return Error.BlockExpected;
        if (word[0] != '[') return Error.BlockExpected;
        return self.block();
    }
};

/// Returns a new `Tsl` instance with the standard bindings.
pub fn standard(allocator: std.mem.Allocator) !Tsl {
    var tsl = try Tsl.init(null, allocator);
    try tsl.set("drucke", Tsl.Value{ .builtin = struct {
        fn doPrint(t: *Tsl) !i64 {
            std.debug.print("{}\n", .{try t.eval()});
            return 0;
        }
    }.doPrint });
    try tsl.set("addiere", Tsl.Value{ .builtin = struct {
        fn doAdd(t: *Tsl) !i64 {
            return try t.eval() + try t.eval();
        }
    }.doAdd });
    try tsl.set("subtrahiere", Tsl.Value{ .builtin = struct {
        fn doSub(t: *Tsl) !i64 {
            return try t.eval() - try t.eval();
        }
    }.doSub });
    try tsl.set("multipliziere", Tsl.Value{ .builtin = struct {
        fn doMul(t: *Tsl) !i64 {
            return try t.eval() * try t.eval();
        }
    }.doMul });
    try tsl.set("dividiere", Tsl.Value{ .builtin = struct {
        fn doDiv(t: *Tsl) !i64 {
            return @divExact(try t.eval(), try t.eval());
        }
    }.doDiv });
    try tsl.set("gleich?", Tsl.Value{ .builtin = struct {
        fn doEq(t: *Tsl) !i64 {
            return if (try t.eval() == try t.eval()) 1 else 0;
        }
    }.doEq });
    try tsl.set("kleiner?", Tsl.Value{ .builtin = struct {
        fn doLt(t: *Tsl) !i64 {
            return if (try t.eval() < try t.eval()) 1 else 0;
        }
    }.doLt });
    try tsl.set("wenn", Tsl.Value{ .builtin = struct {
        fn doIf(t: *Tsl) !i64 {
            var cond = try t.eval();
            var thenBlock = try t.mustBeBlock();
            var elseBlock = try t.mustBeBlock();
            return (if (cond != 0) thenBlock else elseBlock).evalAll();
        }
    }.doIf });
    try tsl.set("solange", Tsl.Value{ .builtin = struct {
        fn doWhile(t: *Tsl) !i64 {
            var cond = try t.mustBeBlock();
            var block = try t.mustBeBlock();
            var result: i64 = 0;
            while (try cond.evalAll() != 0) {
                result = try block.evalAll();
            }
            return result;
        }
    }.doWhile });
    try tsl.set("funktion", Tsl.Value{
        .builtin = struct {
            fn doFunc(t: *Tsl) !i64 {
                const name = try t.next();
                const params = (try t.mustBeBlock()).words;
                const body = (try t.mustBeBlock()).words;
                var value = Tsl.Value{ .function = .{
                    .tsl = t,
                    .params = params,
                    .body = body,
                } };
                try t.set(name, value);
                return 0;
            }
        }.doFunc,
    });
    _ = try tsl.run("funktion minus [a] [subtrahiere 0 a]");
    _ = try tsl.run("funktion nicht [a] [wenn a [0] [1]]");
    _ = try tsl.run("funktion ungleich? [a b] [nicht [gleich? a b]]");
    _ = try tsl.run("funktion groesser? [a b] [kleiner? b a]");
    _ = try tsl.run("funktion kleinergleich? [a b] [nicht [größer? a b]]");
    _ = try tsl.run("funktion größergleich? [a b] [nicht [kleiner? a b]]");

    return tsl;
}

const example = @embedFile("fac.tsl");

pub fn main() !void {
    var allocator = std.heap.page_allocator;
    var tsl = try standard(allocator);
    defer tsl.deinit();
    _ = try tsl.run(example);
}
