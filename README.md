# Erste Schritte mit ZIG

Ich habe mit [Zig](https://ziglang.org/) 0.11 via Homebrew installiert. Danach habe ich das Zig-Plugin für VSC installiert. Nach dem ersten Start will das wissen, welches Zig ich will (das aus dem PATH) und welchen ZLS (Zig Language Server). Hier musste ich ihn entsprechend installieren.

## Hello, World

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

Ein `mkdir tsl; cd tsl; zig init-exe` macht, was ich will. Ansonsten entsteht die `build.zig`-Datei im aktuellen Verzeichnis. In `tsl` with ich eine "tiny scripting language" bauen, denn warum nicht als erstes Projekt gleich einen Interpreter für eine eigene Programmiersprache.

Es sieht für mich so aus, als wenn man `zig-cache`, was ebenfalls angelegt wurde, in `.gitignore` packen. Also:

    echo /zig-cache >.gitignore

Wenn ich jetzt `zig build` eingebe, entsteht auch noch ein `zig-out` Verzeichnis:

    echo /zig-out >>.gitignore

Ich kann nun mit `zig-out/bin/tsl` das übersetzte Programm ausführen. Das wiederum sagt, ich kann auch `zig build test` ausführen und wenn ich das mache, passiert nix. Das scheint aber den im `main.zig` eingebetteten Unit-Test auszuführen, denn wenn ich ihn ändere und mutwillig kaputt mache, beschwert sich Zig. Ein kaputter Test verhindert übrigens kein `zig build`. Dieser Unterbefehl hat gefühlt 1000 Optionen. Aber ich sehe, dass ich `zig build run` machen kann, was wohl das ist, was man in der Regel will.

## TSL

Ich möchte schlussendlich dies ausführen können:

    fakultät: funktion [n] [
        wenn gleich? n 0 [1] [
            multipliziere n fakultät subtrahiere n 1
        ]
    ]
    drucke fakultät 13

Ich beginne aber einfacher mit

    addiere 3 4

und postuliere, dass ein TSL-Programm aus einer Folge von nicht-leeren durch Weißgraum getrennten Wörtern besteht (Klammern sind eine Ausnahme, und trennen ebenfalls) und konsequent von links nach rechts gelesen und ausgewertet wird. Jedes Wort (außer Zahlen) steht dabei für eine Funktion, die weiß, wie viele Argumente sie hat. `addiere` nimmt also die nächsten beiden Ausdrücke, interpretiert diese als Zahlen (Ganzzahlen reichen erst mal) und addiert sie.

Folgt einem Wort ein `:`, ist dies ein "setter" und der gleichnamigen Variable wird das Argument als Wert zugewiesen. Jedes andere Wort (außer Zahlen) ist quasi eine Variable und es wird entweder der Wert zurückgegeben oder wenn es eine Funktion ist, sofort aufgerufen, auf dass diese Funktion sich weitere Argumente holt. Vielleicht ist es einfacher, weil gleichförmiger, wenn ich statt `name: wert` stattdessen ein `set 'name wert` fordere. Das `'` verhindert, dass das Wort ausgewertet wird. Alternativ könnte ich auch `"name"` erwarten, müsste dann aber meine strikte Regel, dass Wörter durch Weißraum getrennt sind, mit "außer sie stehen in Anfühungszeichen" aufweichen. Was ich nicht möchte, ist dass `set` speziell ist, was seine Argumente angeht. Andererseits, das `[` muss auch speziell sein, denn es liefert einen später ausführbaren Block von Wörtern bis zum passenden `]`. Somit kann ich wohl doch `set name wert` erlauben.

### Ein Reader

Beginne ich mit 

```zig
const source = "print add 3 4";
```

ist nun mein erstes Problem, wie ich diesen String in Wörter zerteile und wie ich diese im restlichen Programm repräsentiere. Ich werde dynamisch Speicher reservieren müssen und da ich in Zig meinen Speicher manuell verwalten muss, werde ich das Problem, den auch wieder freigeben zu wollen, erst mal komplott ignorieren.

Copilot schlägt diesen Code vor: 

```zig
var index: usize = 0;

fn readWord() ?[]const u8 {
    var start = index;
    while (index < source.len and source[index] != ' ' and source[index] != '[' and source[index] != ']') {
        index += 1;
    }
    const word = source[start..index];
    // Skip whitespace and brackets
    while (index < source.len and (source[index] == ' ' or source[index] == '[' or source[index] == ']')) {
        index += 1;
    }
    return if (word.len > 0) word else null;
}
```

an einen Typ wie `[]const u8` muss ich mich erst mal gewöhnen. Das `?` sagt, dass er optional ist, weil das Ende der Eingabe durch `null` signalisiert wird. Irgendwie würde ich gerne das globale `index` in ein Objekt kapseln, weiß aber nicht wie. Ansonsten ist der Code relativ simpel. Allerdings geht er davon aus, dass am Anfang keine Leerzeichen stehen können. Und eigentlich ist Weißraum mehr als nur Leerzeichen. Entscheidend ist aber die Idee, dass Wörter keine neuen Strings sind, sondern _slices_ des alten Strings. Das funktioniert, solange wir keine String-Literale mit `\`-Escapesequenzen haben, die wir schon im _reader_ auswerten wollen.

Ich habe übrigens mal geraten und mit `std.ascii.isWhitespace` eine nützliche Funktion gefunden, die natürlich nur Weißraum aus dem ASCII-Bereich von Unicode erkennt. Es gibt zwar auch `std.unicode`, aber da finde ich keine äquivalente Funktion.

Hier ist meine Funktion, wobei ich bei der Implementierung von `isWhitespace` ein bisschen gespickt habe, um mein `isWord` zu bauen:

```zig
fn isWord(c: u8) bool {
    return for ("[]{}()") |other| {
        if (c == other) break false;
    } else !std.ascii.isWhitespace(c);
}

fn nextWord() ?[]const u8 {
    while (index < source.len and std.ascii.isWhitespace(source[index])) {
        index += 1;
    }
    const start = index;
    while (index < source.len and isWord(source[index])) {
        index += 1;
    }
    return if (start < index) source[start..index] else null;
}
```

Copilot hat mir dann folgende `main`-Methode vorgeschlagen, die ich noch für den Typ korrigieren musste. Leider ist `word` auch nach dem `if` immer noch optional, wodurch ich `{?s}` statt `{s}` schreiben muss. Nicht schlimm, aber ich hätte mir eigentlich gewünscht, dass man den Typ einschränken kann

```zig
pub fn main() !void {
    while (true) {
        const word = nextWord();
        if (word == null) {
            break;
        }
        std.debug.print("word: {?s}\n", .{word});
    }
}
```

Vielleicht sollte ich das Ende lieber durch ein leeres Wort signalisieren?

Wichtiger ist aber, dass mein Programm funktioniert:

    word: print
    word: add
    word: 3
    word: 4

Auf der Suche nach Multiline-Strings bin ich auf dieses interessante Konstrukt gestoßen:

```zig
const source = @embedFile("fac.tsl");
```

Damit kann ich das größere Beispiel in eine entsprechend benannte Datei packen und dann als String-Konstante einbinden. Das funktioniert leider nicht mehr, weil ich den Denkfehler gemacht habe, dass ein `[` zwar ein Wort stoppt, aber selbst auch eines sein muss. Letzteres fehlt und `nextWord` denkt, die Eingabe ist zuende.

Ich habe meinen Code daher noch mal umgeschrieben:

```zig
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

fn nextWord() ?[]const u8 {
    while (index < source.len and isWhitespace(source[index])) {
        index += 1;
    }
    if (index == source.len) return null;
    const start = index;
    if (source[index] == ';') {
        index += 1;
        while (index < source.len and source[index] != '\n') {
            index += 1;
        }
    } else if (source[index] == '"') {
        index += 1;
        while (index < source.len and source[index] != '"') {
            index += 1;
        }
    } else if (isParentheses(source[index])) {
        index += 1;
        return source[start..index];
    } else {
        index += 1;
        while (index < source.len and isWord(source[index])) {
            index += 1;
        }
    }
    return source[start..index];
}
```

Jetzt funktioniert auch das Beispiel mit den Klammern. Außerdem habe ich auch noch Unterstützung für Zeilenkommentare mit `;` und Strings in `"` eingebaut. Die Strings dürfen allerdings keine `\"` enthalten und es ist ein Fehler, wenn das schließende `"` fehlt. War daher vielleicht unnötig.

Ich würde diesen Code gerne testen, dazu sollte ich `source` und `index` aber nicht länger lokal haben. Also habe ich Copilot gefrangt:

> Wie kann ich `nextWord` zusammen mit `source` und `index` zu einem Objekt machen?

Dazu soll ich dies machen (und ganz viele `self.` hinzufügen):

```zig
pub const Reader = struct {
    source: []const u8,
    index: usize = 0,

    pub fn nextWord(self: *Reader) ?[]const u8 {
        ...
    }
};
```

Und mein neues `main` sieht so aus:

```zig
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
```

Copilot hat mir nun diesen Test vorgeschlagen, der aber einen Compile-Fehler liefert, wenn ich `zig build test` aufrufen will:

```zig
test "Reader" {
    var r = Reader{ .source = "drucke addiere 3 4" };
    var word = r.nextWord();
    std.testing.expectEqual(word, "drucke");
    word = r.nextWord();
    std.testing.expectEqual(word, "addiere");
    word = r.nextWord();
    std.testing.expectEqual(word, "3");
    word = r.nextWord();
    std.testing.expectEqual(word, "4");
    word = r.nextWord();
    std.testing.expectEqual(word, null);
}
```

Da scheint ein `try` vor jedem `expectEqual` zu fehlen. Danach läufts, allerdings schlagen die Tests fehl, weil ich wohl _slices_ nicht einfach so vergleichen kann. Copilot schlägt (wieder ohne `try`) vor:

```zig
std.testing.expect(std.mem.eql(u8, word, "drucke"))
```

Es gibt auch ein `expectEqualSlices`, das sieht einfacher aus. Kompiliert aber nicht, weil `word` optional ist. Grumpf. Ich ändere das jetzt in `""` steht für das Ende. Dann kann ich `expectEqualStrings` benutzen und der Test läuft.

### Environment

Als nächstes brauche ich eine _Hashmap_, in der ich zu jedem Wort die Funktion nachschauen kann. So etwas muss es doch in der Standardbibliothek geben.

Angeblich funktioniert dies:


```zig
pub const Impl = fn (tsl: *Tsl) i64;

var allocator = std.heap.page_allocator;
var bindings = std.StringHashMap(Impl).init(allocator);
```

Wobei es aber recht umständlich ist, die `bindings` zu initialisieren, weil ich das wohl mit einer Reihe von `try bindings.put()` Befehlen machen muss. Zudem habe ich das Problem, dass `Impl` auf die Struktur `Tsl` verweist, diese aber besagte `bindings` hält und da der Zig-Compiler eine zyklische Abhänigkeit erkennt, die ich nicht so einfach auflösen kann.

Auch Copilot hilft mir nicht und letztlich nach einigem _trial & error_ verzichte ich auf den Alias und nutze `*const fn (*Tsl) i64` an allen Stellen.

Ich gestehe, ich habe nicht wirklich verstanden, wann ich Pointer und wann nicht benutzen soll oder muss und ich weiß auch noch nicht, wie ich in einer HashMap sowohl Zahlen als auch Funktionen speichere.

Nach vielen Versuchen sieht meine Initialisierung nun so aus:

```zig
pub fn main() !void {
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
```

Ich habe es nicht hinbekommen, die Funktionen dort _inline_ zu definieren. Es scheint auch keinen Weg zu geben, den _slice_ der Wörter direkt zu übergeben. 

Alles in allem wirkt das sehr umständlich.

Ich will nun meinen `Reader` mit dem Interpreter `Tsl` verbinden. Nach einigem Probieren kapsle ich das Aufsplitten des Strings in ein _slice_ in einer neuen Funktion `split`, die ebenfalls wieder Speicher reservieren muss und für die ich daher einen `Allocator` brauche:

```zig
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
```

Das Erzeugen eines Interpreters lagere ich in die Funktion `standard` aus (wo ich jetzt einen Weg gefunden habe, die Implementierungen _inline_ zu defineren):

```zig
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
```

Mein `main` ist jetzt erfreulich kurz (es _leaked_ jedoch den angeforderten Speicher, wahrscheinlich muss ich irgendwann noch eine `deinit`-Methode für `Tsl` schreiben, wofür ich mir wohl den `Allocator` merken müsste):

```
pub fn main() !void {
    var allocator = std.heap.page_allocator;
    var tsl = try standard(allocator);
    _ = tsl.run(try split("drucke addiere 3 4", allocator));
}
```

Als nächstes will ich nicht einfach -1 oder -2 in `eval` zurück geben, sondern "echte" Fehler werden. Dafür müssen die Signaturen von `i64` in `Error!i64` geändert werden und ich muss mir Fehler als `error` _enumeration_ definieren.

```zig
pub Tsl = struct {
    ...

    const Error = error{
        EndOfInput,
        UnknownWord,
    };

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
        var result: i64 = 0;
        while (self.index < self.words.len) {
            result = try self.eval();
        }
        return result;
    }
}
```

Außerdem muss ich jetzt überall `try eval` statt nur `eval` schreiben.
