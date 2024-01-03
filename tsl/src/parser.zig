const std = @import("std");

const str = []const u8;

/// A "result" type that is either a parsing success combining a result
/// value and the remaining input or a failure with an error message.
fn Result(comptime _T: type, comptime _I: type) type {
    return union(enum) {
        const T = _T;
        const I = _I;

        success: struct {
            value: T,
            rest: I,
        },
        failure: str,

        fn success(value: T, rest: I) Result(T, I) {
            return .{ .success = .{ .value = value, .rest = rest } };
        }

        fn failure(message: str) Result(T, I) {
            return .{ .failure = message };
        }
    };
}

pub fn Parser(comptime P: type) type {
    switch (@typeInfo(@TypeOf(@field(P, "parse")))) {
        .Fn => |f| {
            if (f.params[0].type.? != f.return_type.?.I) {
                @panic("parse function has wrong type");
            }
        },
        else => unreachable,
    }

    return struct {
        const Self = @This();

        const Result = (switch (@typeInfo(@TypeOf(@field(P, "parse")))) {
            .Fn => |f| f.return_type.?,
            else => unreachable,
        });

        pub usingnamespace P;
    };
}

fn Char(comptime c: u8) type {
    return Parser(struct {
        fn parse(input: str) Result(u8, str) {
            if (input.len > 0 and input[0] == c) {
                return Result(u8, str).success(input[0], input[1..]);
            }
            return Result(u8, str).failure("expected char");
        }
    });
}

fn Alt(comptime p1: type, comptime p2: type) type {
    const R = p1.Result;
    if (p2.Result != R) {
        @panic("both parsers need the same result type");
    }

    return Parser(struct {
        var buf: [1024]u8 = undefined;

        fn parse(input: R.I) R {
            return switch (p1.Self.parse(input)) {
                .success => |s1| R.success(s1.value, s1.rest),
                .failure => |f1| switch (p2.Self.parse(input)) {
                    .success => |s2| R.success(s2.value, s2.rest),
                    .failure => |f2| R.failure(std.fmt.bufPrint(&buf, "{s} or {s}", .{ f1, f2 }) catch "?"),
                },
            };
        }
    });
}

fn Rep(comptime p: type) type {
    const R = Result([]p.Result.T, p.Result.I);
    return Parser(struct {
        var results: [1024]p.Result.T = undefined;

        fn parse(input: R.I) R {
            var i: usize = 0;
            var rest = input;
            while (true) {
                switch (p.Self.parse(rest)) {
                    .success => |s| {
                        results[i] = s.value;
                        rest = s.rest;
                    },
                    .failure => return R.success(results[0..i], rest),
                }
            }
        }
    });
}

pub fn main() void {
    const Ca = Char('a');
    const Cb = Char('b');
    const P = Rep(Alt(Ca, Cb));
    var r = P.Self.parse("abbc");
    std.debug.print("{}\n", .{r});
    std.debug.print("{s}\n", .{switch (r) {
        .success => |s| s.value,
        else => "-",
    }});
}
