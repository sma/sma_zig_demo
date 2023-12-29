Erste Schritte mit ZIG

Ich habe mit [Zig](https://ziglang.org/) 0.11 via Homebrew installiert. Danach habe ich das Zig-Plugin für VSC installiert. Nach dem ersten Start will das wissen, welches Zig ich will (das aus dem PATH) und welchen ZLS (Zig Language Server). Hier musste ich ihn entsprechend installieren.

Dann habe ich folgendes in `main.zig` abgetippt:

```zig
const std = @import("std");

pub fn main() void {
    std.debug.print("Hello, {s}!\n", .{ "world" });
}
```

Das Beispiel stammt aus [diesem Video](https://www.youtube.com/watch?v=5I4ZkmMS4-0), das ich mir zur Einführung angeschaut habe. Das kann ich mir zwar unmöglich alles merken, aber vielleicht erinnere ich mich später an die Besonderheiten. Merkwürdigerweise sagt es nicht, wie ich obiges Programm auch ausführe. 

Das geht mit `zig run main.zig`. Oder ich rufe `zig build-exe main.zig` auf und erhalte eine `.o`-Datei und eine "exe" namens `main`.

Offenbar erwartet Zig aber, dass ich ein Projekt anlege, denn es will eine `build.zig`-Datei ausführen, wenn ich einfach nur `zig build` eingebe und es gibt auch `zig init-exe`, was wohl ein solches Projekt anlegt. Probieren wir es aus.


