const std = @import("std");

const source = @embedFile("fac.tsl");

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
    bindings: std.StringHashMap(*const fn (*Tsl) i64),
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

    pub fn block(self: *Tsl) Tsl {
        const start = self.index;
        var count = 1;
        while (count > 0) {
            const word = self.next();
            if (word.len == 0) {
                std.debug.assert(false, "unbalanced block");
            }
            if (word[0] == '[') {
                count += 1;
            } else if (word[0] == ']') {
                count -= 1;
            }
        }
        return Tsl{
            .bindings = self.bindings,
            .words = self.words[start .. self.index - 1],
        };
    }

    pub fn eval(self: *Tsl) i64 {
        const word = self.next();
        if (word.len == 0) return -1;
        if (self.bindings.get(word)) |impl| {
            return impl(self);
        }
        return std.fmt.parseInt(i64, word, 10) catch -2;
    }

    pub fn run(self: *Tsl, words: [][]const u8) i64 {
        self.words = words;
        self.index = 0;
        var result: i64 = 0;
        while (self.index < self.words.len) {
            result = self.eval();
        }
        return result;
    }
};

pub fn standard(allocator: std.mem.Allocator) !Tsl {
    var bindings = std.StringHashMap(*const fn (*Tsl) i64).init(allocator);
    try bindings.put("drucke", struct {
        fn doPrint(t: *Tsl) i64 {
            std.debug.print("{}\n", .{t.eval()});
            return 0;
        }
    }.doPrint);
    try bindings.put("addiere", struct {
        fn doAdd(t: *Tsl) i64 {
            return t.eval() + t.eval();
        }
    }.doAdd);
    return Tsl{
        .bindings = bindings,
        .words = &[_][]const u8{},
    };
}

pub fn main() !void {
    var allocator = std.heap.page_allocator;
    var tsl = try standard(allocator);
    _ = tsl.run(try split("drucke addiere 3 4", allocator));
}
