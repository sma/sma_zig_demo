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

pub fn main() !void {
    var r = Reader{ .source = "drucke addiere 3 4" };
    while (true) {
        const word = r.nextWord();
        if (word == null) {
            break;
        }
        std.debug.print("word: {?s}\n", .{word});
    }
}
