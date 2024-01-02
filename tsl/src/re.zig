const std = @import("std");
const pcre2 = @cImport(@cInclude("pcre2posix.h"));

/// An experiment to call the POSIX regex C library from Zig.
///
/// Use
///
///     zig test -I/usr/local/include -lpcre2-posix src/re.zig
///
/// to run the example.
pub const RegEx = struct {
    const Error = error{InvalidPattern};

    regex: pcre2.regex_t,
    allocator: std.mem.Allocator,
    initialized: bool = false,

    pub fn init(pattern: []const u8, allocator: std.mem.Allocator) !RegEx {
        var re = RegEx{
            .regex = undefined,
            .allocator = allocator,
        };

        // using this with `REG_PEND`, we don't need a null-terminated string
        re.regex.re_endp = @ptrCast(pattern);
        re.regex.re_endp += pattern.len;

        // compile the pattern and initialize `regex`
        if (pcre2.regcomp(&re.regex, @ptrCast(pattern), pcre2.REG_PEND | pcre2.REG_EXTENDED | pcre2.REG_UTF) != 0) {
            return Error.InvalidPattern;
        }

        // so `deinit` can savely called twice
        re.initialized = true;

        return re;
    }

    pub fn deinit(self: *RegEx) void {
        if (self.initialized) {
            self.initialized = false;
            pcre2.regfree(&self.regex);
        }
    }

    /// Returns the first match or `null`.
    pub fn matchOne(self: *RegEx, input: []const u8) ?[]const u8 {
        // using this with `REG_STARTEND`, we don't need a null-terminated string
        var m = pcre2.regmatch_t{ .rm_so = 0, .rm_eo = @intCast(input.len) };

        // search the input
        if (pcre2.regexec(&self.regex, @ptrCast(input), 1, &m, pcre2.REG_STARTEND) != 0) {
            return null;
        }

        // found something
        var start: usize = @intCast(m.rm_so);
        var end: usize = @intCast(m.rm_eo);
        return input[start..end];
    }

    /// Returns all matches. The caller must free the result.
    pub fn matchAll(self: *RegEx, input: []const u8) ![][]const u8 {
        // to collect the matches
        var matches = std.ArrayList([]const u8).init(self.allocator);

        // using this with `REG_STARTEND`, we don't need a null-terminated string
        var m = pcre2.regmatch_t{ .rm_so = 0, .rm_eo = @intCast(input.len) };

        // search the input, one match at a time
        while (true) {
            if (pcre2.regexec(&self.regex, @ptrCast(input), 1, &m, pcre2.REG_STARTEND) != 0) {
                return matches.toOwnedSlice(); // need to free this
            }

            // found something
            var start: usize = @intCast(m.rm_so);
            var end: usize = @intCast(m.rm_eo);
            try matches.append(input[start..end]);
            m.rm_so = @intCast(end);
            m.rm_eo = @intCast(input.len);
        }
    }
};

test "matchOne" {
    var a = std.testing.allocator;

    var r = try RegEx.init("\\d+ \\d+", a);
    defer r.deinit();
    var m = r.matchOne(" 94 343---1") orelse "";
    try std.testing.expectEqualStrings("94 343", m);
}

test "matchAll" {
    var a = std.testing.allocator;

    var r = try RegEx.init("\\S+", a);
    defer r.deinit();
    var matches = try r.matchAll(" 94 343---1 a ccc ");
    defer a.free(matches);

    try std.testing.expectEqual(@as(usize, 4), matches.len);
    try std.testing.expectEqualStrings("94", matches[0]);
    try std.testing.expectEqualStrings("343---1", matches[1]);
    try std.testing.expectEqualStrings("a", matches[2]);
    try std.testing.expectEqualStrings("ccc", matches[3]);
}
