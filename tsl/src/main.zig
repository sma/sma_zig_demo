const std = @import("std");

const source = @embedFile("fac.tsl");

pub const Reader = struct {
    source: []const u8,
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
        while (self.index < self.source.len and isWhitespace(self.source[self.index])) {
            self.index += 1;
        }
        if (self.index == self.source.len)
            return self.source[self.index..self.index];
        const start = self.index;
        if (self.source[self.index] == ';') {
            self.index += 1;
            while (self.index < self.source.len and self.source[self.index] != '\n') {
                self.index += 1;
            }
        } else if (self.source[self.index] == '"') {
            self.index += 1;
            while (self.index < self.source.len and self.source[self.index] != '"') {
                self.index += 1;
            }
            if (self.index < self.source.len) {
                self.index += 1;
            }
        } else if (isParentheses(self.source[self.index])) {
            self.index += 1;
            return self.source[start..self.index];
        } else {
            self.index += 1;
            while (self.index < self.source.len and isWord(self.source[self.index])) {
                self.index += 1;
            }
        }
        return self.source[start..self.index];
    }
};

test "Reader" {
    var r = Reader{ .source = "[3 \"[]\" drucke]" };
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

fn doPrint(t: *Tsl) i64 {
    std.debug.print("{}\n", .{t.eval()});
    return 0;
}

fn doAdd(t: *Tsl) i64 {
    return t.eval() + t.eval();
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
};

pub fn main() !void {
    // var r = Reader{ .source = "drucke addiere 3 4" };

    var allocator = std.heap.page_allocator;
    var bindings = std.StringHashMap(*const fn (*Tsl) i64).init(allocator);
    try bindings.put("drucke", doPrint);
    try bindings.put("addiere", doAdd);
    var words = [_][]const u8{
        "drucke",
        "addiere",
        "3",
        "addiere",
        "4",
        "5",
    };
    var tsl = Tsl{
        .bindings = bindings,
        .words = words[0..],
    };
    _ = tsl.eval();
}
