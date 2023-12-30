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
        BlockExpeced,
        EndOfInput,
        UnknownWord,
    };

    allocator: std.mem.Allocator,
    bindings: std.StringHashMap(*const fn (*Tsl) Error!i64),
    words: [][]const u8,
    index: usize = 0,

    pub fn next(self: *Tsl) []const u8 {
        if (self.index == self.words.len) {
            return "";
        }
        const word = self.words[self.index];
        self.index += 1;
        return word;
    }

    pub fn block(self: *Tsl) Error!Tsl {
        const start = self.index;
        var count: usize = 1;
        while (count > 0) {
            const word = self.next();
            if (word.len == 0) {
                return Error.UnbalancedBlock;
            }
            if (word[0] == '[') {
                count += 1;
            } else if (word[0] == ']') {
                count -= 1;
            }
        }
        return Tsl{
            .allocator = self.allocator,
            .bindings = self.bindings,
            .words = self.words[start .. self.index - 1],
        };
    }

    pub fn eval(self: *Tsl) Error!i64 {
        const word = self.next();
        if (word.len == 0) return Error.EndOfInput;
        if (self.bindings.get(word)) |impl| {
            return try impl(self);
        }
        return std.fmt.parseInt(i64, word, 10) catch {
            return Error.UnknownWord;
        };
    }

    pub fn run(self: *Tsl, words: [][]const u8) Error!i64 {
        self.words = words;
        self.index = 0;
        return self.evalAll();
    }

    fn evalAll(self: *Tsl) Error!i64 {
        var result: i64 = 0;
        while (self.index < self.words.len) {
            result = try self.eval();
        }
        return result;
    }

    fn mustBeBlock(self: *Tsl) Error!Tsl {
        var word = self.next();
        if (word.len == 0) return Error.EndOfInput;
        if (word[0] != '[') return Error.BlockExpeced;
        return self.block();
    }

    fn userFn(self: *Tsl, params: [][]const u8, body: [][]const u8) *const fn (*Tsl) Error!i64 {
        const U = struct {
            t: *Tsl,
            params: [][]const u8,
            body: [][]const u8,
            fn call(u: *const @This()) Error!i64 {
                var tt = Tsl{
                    .allocator = u.t.allocator,
                    .bindings = u.t.bindings,
                    .words = u.body,
                };
                var i: usize = 0;
                while (i < u.params.len) {
                    try tt.bindings.put(u.params[i], struct {
                        fn param(t: *Tsl) !i64 {
                            return try t.eval();
                        }
                    }.param);
                    i += 1;
                }
                return tt.evalAll();
            }
        };
        var u = U{
            .t = self,
            .params = params,
            .body = body,
        };
        return u.call;
    }
};

pub fn standard(allocator: std.mem.Allocator) !Tsl {
    var bindings = std.StringHashMap(*const fn (*Tsl) Tsl.Error!i64).init(allocator);
    try bindings.put("drucke", struct {
        fn doPrint(t: *Tsl) !i64 {
            std.debug.print("{}\n", .{try t.eval()});
            return 0;
        }
    }.doPrint);
    try bindings.put("addiere", struct {
        fn doAdd(t: *Tsl) !i64 {
            return try t.eval() + try t.eval();
        }
    }.doAdd);
    try bindings.put("subtrahiere", struct {
        fn doSub(t: *Tsl) !i64 {
            return try t.eval() - try t.eval();
        }
    }.doSub);
    try bindings.put("multipliziere", struct {
        fn doMul(t: *Tsl) !i64 {
            return try t.eval() * try t.eval();
        }
    }.doMul);
    try bindings.put("gleich?", struct {
        fn doEq(t: *Tsl) !i64 {
            return if (try t.eval() == try t.eval()) 1 else 0;
        }
    }.doEq);
    try bindings.put("wenn", struct {
        fn doIf(t: *Tsl) !i64 {
            var cond = try t.eval();
            var thenBlock = try t.mustBeBlock();
            var elseBlock = try t.mustBeBlock();
            return (if (cond != 0) thenBlock else elseBlock).evalAll();
        }
    }.doIf);
    try bindings.put("funktion", struct {
        fn doFunc(t: *Tsl) !i64 {
            var name = t.next(); // this should raise the error
            if (name.len == 0) return Tsl.Error.EndOfInput;
            const params = (try t.mustBeBlock()).words;
            const body = (try t.mustBeBlock()).words;
            const func = t.userFn(params, body);
            _ = func;
            // try t.bindings.put(name, func);
            return 0;
        }
    }.doFunc);
    return Tsl{
        .allocator = allocator,
        .bindings = bindings,
        .words = &[_][]const u8{},
    };
}

const example = @embedFile("fac.tsl");

pub fn main() !void {
    var allocator = std.heap.page_allocator;
    var tsl = try standard(allocator);
    _ = try tsl.run(try split(example, allocator));
    allocator.free(tsl.words);
    tsl.bindings.deinit();
}
