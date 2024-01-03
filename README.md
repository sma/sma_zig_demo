# Erste Schritte mit Zig

Ich habe mir [Zig](https://ziglang.org/) 0.11 via Homebrew installiert. Danach habe ich das Zig-Plugin für VSC installiert. Nach dem ersten Start will das Plugin wissen, welche Zig-Version ich will (das aus dem PATH) und welchen ZLS (Zig Language Server). Hier musste ich ihn entsprechend nach-installieren.

## Hello, World

Dann habe ich folgendes in `main.zig` abgetippt:

```zig
const std = @import("std");

pub fn main() void {
    std.debug.print("Hello, {s}!\n", .{ "world" });
}
```

Das Beispiel stammt aus [diesem Video](https://www.youtube.com/watch?v=5I4ZkmMS4-0), das ich mir zur Einführung angeschaut habe. Das kann ich mir zwar unmöglich alles merken, aber vielleicht erinnere ich mich später an die Besonderheiten.

Merkwürdigerweise sagt es nicht, wie ich obiges Programm ausführe. 

Das geht mit `zig run main.zig`. Oder ich rufe `zig build-exe main.zig` auf und erhalte eine `.o`-Datei und eine "exe" namens `main`. Die kann ich dann wie gewohnt mit `./main` aufrufen.

Offenbar erwartet Zig aber, dass ich ein Projekt anlege, denn es will eine `build.zig`-Datei ausführen, wenn ich einfach nur `zig build` eingebe und es gibt auch `zig init-exe`, was wohl ein solches Projekt anlegt.

Probieren wir es aus.

Ein `mkdir tsl; cd tsl; zig init-exe` macht, was ich will. Ansonsten entsteht die `build.zig`-Datei im aktuellen Verzeichnis. In `tsl` with ich eine "tiny scripting language" bauen, denn warum nicht als erstes Projekt gleich einen Interpreter für eine eigene Programmiersprache?

Es sieht für mich so aus, als wenn man `zig-cache`, was ebenfalls angelegt wurde, in `.gitignore` packen. Also:

    echo /zig-cache >.gitignore

Wenn ich jetzt `zig build` eingebe, entsteht auch noch ein `zig-out` Verzeichnis:

    echo /zig-out >>.gitignore

Ich kann danach mit `zig-out/bin/tsl` das übersetzte Programm ausführen.

Das wiederum sagt, ich kann auch `zig build test` ausführen und wenn ich das mache, passiert nix. Dieser Befehl scheint den im `main.zig` eingebetteten Unit-Test auszuführen und bei Erfolg einfach mal nix auszugeben. Denn wenn ich ihn ändere und mutwillig kaputt mache, beschwert sich Zig recht unübersichtlich. Ein kaputter Test verhindert übrigens kein erfolgreiches `zig build`. Nachtrag: Tatsächlich kann der Quelltext sogar Fehler enthalten, die nicht weiter stören, solange dieser Code nicht von `main` aus erreichbar ist. Damit bin ich einige Male reingefallen. Der `build`-Unterbefehl hat gefühlt 1000 Optionen. Aber ich sehe, dass ich `zig build run` machen kann, was wohl das ist, was man in der Regel will.

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

und postuliere, dass ein TSL-Programm aus einer Folge von nicht-leeren durch Weißraum getrennten Wörtern besteht (eckige Klammern sind eine Ausnahme und trennen ebenfalls damit ich nicht `[ n ]` schreiben muss) und konsequent von links nach rechts gelesen und ausgewertet wird. Jedes Wort (außer Zahlen) steht dabei für eine Funktion, die weiß, wie viele Argumente sie hat. `addiere` nimmt die nächsten beiden Ausdrücke, interpretiert diese als Zahlen (Ganzzahlen reichen erst mal) und addiert sie. Das würde rekursiv auch für `addiere addiere 3 4 5` oder `addiere 3 addiere 4 5` funktionieren.

Folgt einem Wort ein `:`, ist dies ein "setter" und der gleichnamigen Variable wird das Argument als Wert zugewiesen. Jedes andere Wort (außer Zahlen) ist quasi eine Variable und es wird entweder der Wert zurückgegeben oder wenn es eine Funktion ist, sofort wie gerade beschrieben ausgeführt, auf dass diese Funktion sich weitere Argumente holt. 

Vielleicht ist es einfacher, weil gleichförmiger, wenn ich statt `name: wert` stattdessen ein `set name wert` fordere. Dieser Befehl ist dann speziell, als dass er sein erstes Argument _nicht_ auswertet sondern dort immer ein Wort erwartet. Nachtrag: Letztlich habe ich mich für `funktion fac [..] [..]` entschieden und damit die Funktionalität von `set` mit in `funktion` gezogen. Dieses Wort erwartet ein nicht auszuwertendes Wort als erstes Argument, gefolgt von zwei Blöcken.

Auch diese sind speziell. Das Wort `[` wertet gar nichts aus, sondern liest solange Wörter ein, bis das passende `]` gefunden wird. Dabei werden verschachtelte Klammern mitgezählt. Das Wort `]` werde ich dann als Fehler implementieren, für den Fall, dass man vielleicht `[]]` schreibt und der Interpreter auf einmal auf ein einsames `]` stößt.

### Ein Reader

Beginne ich mit 

```zig
const source = "drucke addiere 3 4";
```

ist nun mein erstes Problem, wie ich diesen String in Wörter zerteile und wie ich diese im restlichen Programm repräsentiere. Ich werde dynamisch Speicher reservieren müssen. Da ich in Zig meinen Speicher manuell verwalten muss, werde ich das Problem, den auch wieder freigeben zu wollen, erst mal komplott ignorieren.

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

An einen Typ wie `?[]const u8` muss ich mich erst mal gewöhnen. 

Das `?` sagt, dass er optional ist, weil das Ende der Eingabe durch `null` signalisiert wird. Das `[]` steht für ein Array und `const u8` meint, dass das Array aus nicht veränderbaren 8-bit-Integern (als Bytes) besteht. Einen speziellen String-Typ kennt Zig nicht.

Ich würde gerne das globale `index` in ein Objekt kapseln, weiß aber (noch) nicht wie. Ansonsten ist der Code relativ simpel. Allerdings geht er davon aus, dass am Anfang keine Leerzeichen stehen können. Und eigentlich ist Weißraum mehr als nur Leerzeichen. Entscheidend ist aber die Idee, dass Wörter keine neuen Strings sind, sondern _slices_ des alten Strings. Das funktioniert, solange wir keine String-Literale mit `\`-Escapesequenzen haben, die wir schon im _reader_ auswerten wollen. Damit kann ich erst mal leben.

Ich habe übrigens mal geraten und mit `std.ascii.isWhitespace` eine nützliche Funktion gefunden, die natürlich nur Weißraum aus dem ASCII-Bereich von Unicode erkennt. Es gibt zwar auch `std.unicode`, aber da finde ich keine äquivalente Funktion.

Hier ist meine eigene Funktion, wobei ich bei der Implementierung von `isWhitespace` ein bisschen gespickt habe, um mein `isWord` zu bauen:

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

Copilot hat mir dann folgende `main`-Methode vorgeschlagen, die ich noch für den Typ korrigieren musste. Leider ist `word` auch nach dem `if` immer noch optional, wodurch ich `{?s}` statt `{s}` schreiben muss. Nicht schlimm, aber ich hätte mir eigentlich gewünscht, dass man den Typ einschränken kann. 

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

Nachtrag: Dies ist ideomatisches Zig:

```zig
pub fn main() !void {
    while (nextWord()) |word| {
        std.debug.print("{s}\n", .{word});
    }
}
```

Vielleicht sollte ich das Ende lieber durch ein leeres Wort signalisieren?

Wichtiger ist aber, dass mein Programm funktioniert:

    word: drucke
    word: addiere
    word: 3
    word: 4

Auf der Suche nach Multiline-Strings bin ich auf dieses interessante Konstrukt gestoßen:

```zig
const source = @embedFile("fac.tsl");
```

Damit kann ich das größere Beispiel in eine entsprechend benannte Datei packen und dann als Compile-Zeit-String-Konstante einbinden. Dieses Beispiel funktioniert leider nicht, weil ich bei `nextWord` den Denkfehler gemacht habe, dass ein `[` zwar ein Wort stoppt, aber selbst auch eines sein muss. Letzteres fehlt und `nextWord` denkt, die Eingabe ist zuende.

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

Jetzt funktioniert auch das Beispiel mit den Klammern. Außerdem habe ich auch noch Unterstützung für Zeilenkommentare mit `;` und Strings in `"` eingebaut. Die Strings dürfen allerdings selbst keine `\"` enthalten und es ist ein Fehler, wenn das schließende `"` fehlt, den ich nicht bemerke. War daher vielleicht unnötig.

Ich würde diesen Code gerne testen, dazu sollte ich `source` und `index` aber nicht länger lokal haben. Also habe ich Copilot gefragt:

> Wie kann ich `nextWord` zusammen mit `source` und `index` zu einem Objekt machen?

Dazu soll ich dies machen (und ganz viele `self.` hinzufügen um aus `source` jetzt `self.source` bzw. aus `index` jetzt `self.index` zu machen):

```zig
pub const Reader = struct {
    source: []const u8,
    index: usize = 0,

    pub fn nextWord(self: *Reader) ?[]const u8 {
        ...
    }
};
```

Das `pub` steht übrigens für "public" und würde ich meinen `Reader` in eine eigene Datei schreiben und dann mit `@import` einbinden, könnte ich nur auf diese Dinge zugreifen.

Mein neues `main` sieht so aus:

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

Nachtrag: Ideomatisches Zig würde eine `init`-Funktion zu `Reader` hinzufügen, sodass man `Reader.init("drucke addiere 3 4")` schreiben könnte, denke ich.

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

Da scheint ein `try` vor jedem `expectEqual` zu fehlen. Danach läufts, allerdings schlagen alle Tests fehl, weil ich wohl _slices_ nicht einfach so mit String-Literalen vergleichen kann. Copilot schlägt (immer noch ohne `try`) vor:

```zig
std.testing.expect(std.mem.eql(u8, word, "drucke"))
```

Es gibt auch ein `expectEqualSlices`, das sieht einfacher aus. Kompiliert aber nicht, weil `word` optional ist. Grumpf. Ich ändere die Implementierung, dass ein Leerstrings (bzw. eine leere _slice_) für das Ende steht. Dann kann ich `expectEqualStrings` benutzen und der Test läuft.

### Environment

Als nächstes brauche ich eine _Hashmap_, in der ich zu jedem Wort die Funktion nachschauen kann. So etwas muss es doch in der Standardbibliothek geben.

Angeblich (laut Copilot) funktioniert dies:


```zig
pub const Impl = fn (tsl: *Tsl) i64;

var allocator = std.heap.page_allocator;
var bindings = std.StringHashMap(Impl).init(allocator);
```

Wobei es aber recht umständlich ist, die `bindings` zu initialisieren, weil ich das wohl mit einer Reihe von `try bindings.put()` Befehlen machen muss. Zudem habe ich das Problem, dass `Impl` auf die Struktur `Tsl` verweist, diese aber besagte `bindings` hält und da der Zig-Compiler eine zyklische Abhänigkeit erkennt, die ich nicht so einfach auflösen kann.

Auch Copilot hilft mir nicht weiter und letztlich nach ziemlich viel _trial & error_ verzichte ich auf den _Alias_ und nutze `*const fn (*Tsl) i64` an allen Stellen.

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

Ich habe es nicht hinbekommen, die Funktionen _inline_ zu definieren. Es scheint auch keinen Weg zu geben, den _slice_ der Wörter direkt zu übergeben. 

Alles in allem wirkt das sehr umständlich.

Ich sollte vielleicht auch noch `Tsl` zeigen:

```zig
const Tsl = struct {
    bindings: std.StringHashMap(*const fn (*Tsl) i64),
    words: []const []const u8,
    index: usize = 0,

    fn next(self: *Tsl) []const u8 {
        if (self.index == self.words.len) return "";
        const word = self.words[self.index];
        self.index += 1;
        return word;
    }

    fn block(self: *Tsl) [][]const u8 {
        const start = self.index;
        var count: usize = 1;
        while (count > 0) {
            const word = self.next();
            if (word.len == 0) break; // error
            if (word[0] == '[') count += 1;
            if (word[0] == ']') count -= 1;
        }
        return self.words[start .. self.index - 1];
    }

    fn eval(self: *Tsl) i64 {
        const word = self.next();
        if (word.len == 0) return -1; // error
        if (self.bindings.get(word)) |impl| return impl(self);
        return std.fmt.parseInt(i64, word, 10) catch -2;
    }
};
```

Das `get` habe ich so erfragt und auch das `catch` ist nett, um statt eines Fehlers etwas anderes zurück geben zu können. Fehlermeldungen habe ich erst mal komplett ausgeklammert.

Mit diesen Funktionen funktioniert dann mein Beispiel:

```zig
fn doPrint(self: *Tsl) i64 {
    std.debug.print("{d}\n", .{self.eval()});
    return 0;
}

fn doAdd(self: *Tsl) i64 {
    return self.eval() + self.eval();
}
```

### Strings parsen

Ich will nun meinen `Reader` mit dem Interpreter `Tsl` verbinden. Nach einigem Probieren kapsle ich das Aufsplitten des Strings in ein _slice_ of _slices_ in einer neuen Funktion `split`, die ebenfalls wieder Speicher reservieren muss und für die ich daher genau wie bei `StringHashMap` einen `Allocator` brauche, weil sie intern eine `ArrayList` benutzt.

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

Das Erzeugen eines Interpreters lagere ich in die Funktion `standard` aus (wo ich jetzt einen Weg gefunden habe, die Implementierungen mit Hilfe von `struct`s _inline_ zu defineren):

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

Mein `main` ist jetzt erfreulich kurz (es _leaked_ jedoch den angeforderten Speicher, wahrscheinlich muss ich irgendwann noch eine `deinit`-Methode für `Tsl` schreiben, wofür ich mir wohl den `Allocator` merken müsste…):

```
pub fn main() !void {
    var allocator = std.heap.page_allocator;
    var tsl = try standard(allocator);
    _ = tsl.run(try split("drucke addiere 3 4", allocator));
}
```

So sieht das fehlende `run` aus:

```zig
const Tsl = struct {
    ...

    fn run(self: *Tsl, words: []const []const u8) i64 {
        self.words = words;
        self.index = 0;
        var result: i64 = 0;
        while (self.index < self.words.len) {
            result = self.eval();
        }
        return result;
    }
};
```

### Echte Fehler

Als nächstes will ich nicht einfach -1 oder -2 in `eval` zurück geben, sondern "echte" Fehler werden. Dafür müssen die Signaturen von `i64` in `Error!i64` geändert werden und ich muss mir Fehler als `error` _enumeration_ definieren.

```zig
pub Tsl = struct {
    const Error = error{ EndOfInput, UnknownWord };

    bindings: std.StringHashMap(*const fn (*Tsl) Error!i64),

    ...

    fn eval(self: *Tsl) Error!i64 {
        const word = self.next();
        if (word.len == 0) return Error.EndOfInput;
        if (self.bindings.get(word)) |impl| return impl(self);
        return std.fmt.parseInt(i64, word, 10) catch Error.UnknownWord;
    }

    fn evalAll(self: *Tsl) Error!i64 {
        var result: i64 = 0;
        while (self.index < self.words.len) {
            result = try self.eval();
        }
        return result;
    }

    fn run(self: *Tsl, words: []const []const u8) Error!i64 {
        self.words = words;
        self.index = 0;
        return self.evalAll();
    }
}
```

Außerdem muss ich jetzt überall `try eval` statt nur `eval` schreiben.

### Fakultät

Es ist an der Zeit, das große Beispiel anzugehen. Implementierungen für  `multipliziere`, `subtrahiere`, `gleich?` und `wenn` sind einfach hinzuzufügen. Doch ein `funktion fakultät [n] [...]` (ich werde ein Wort definieren, dass eine neue benutzerdefinierte Funktion erzeugt, weil mein `eval` aktuell nur Zahlen unterstützt – daher musste ich schon _booleans_ für `wenn` mit 1 und 0 repräsentieren) stellt mich vor Probleme.

Zig scheint keine _Closures_ zu kennen, die ich benutzen wollte:

```zig
pub fn standard(allocator: std.mem.Allocator) !Tsl {
    ...
    
    try bindings.put("funktion", struct {
        fn doFunc(t: *Tsl) !i64 {
            var name = t.next(); // this should raise the error
            if (name.len == 0) return Tsl.Error.EndOfInput;
            var params = (try t.mustBeBlock()).words;
            var body = (try t.mustBeBlock()).words;
            try t.bindings.put(name, struct {
                fn userFn(t1: *Tsl) !i64 {
                    var tt = Tsl{
                        .bindings = std.StringHashMap(*const fn (*Tsl) Tsl.Error!i64).init(allocator),
                        .words = body,
                    };
                    var i: usize = 0;
                    while (i < params.len) {
                        const v = try t1.eval();
                        try tt.bindings.put(params[i], struct {
                            fn param(_: *Tsl) !i64 {
                                return v;
                            }
                        }.param);
                        i += 1;
                    }
                    return tt.evalAll();
                }
            }.userFn);
            return 0;
        }
    }.doFunc);
```

Oder funktioniert das doch? Wenn ich an strategischen Stellen `const` statt `var` benutze, scheint die Variable _captured_ zu werden. Allerdings bekomme ich den `allocator` Paramter nicht übergeben. Ich hatte aber eh überlegt, ob ich ihn nicht in `Tsl` mir merken sollte. Allerdings hat zwar jetzt die IDE keine Probleme mehr, der Zig-Compiler mag aber trotzdem nicht auf `params` oder `body` aus der inneren Funktion zugreifen.

Ich habe jetzt bestimmt zwei Stunden herumprobiert und auch wenn Copilot auf die nun eingecheckte Lösung besteht … sie funktioniert nicht. Und ich habe inzwischen verstanden, das Zig keine _Closures_ kann, finde aber auch keinen Workaround, da es mir nicht gelingt, eine Funktion in irgendeinem Kontext zu definieren. 

Ich gebe auf.

### Unions für Werte

Neuer Tag. Ich muss als Werte in den `bindings` mehr als nur `i64` speichern können. Eine _tagged union_ scheint mir der richtige Weg zu sein und diese kann ich dann auch nutzen, um neben Zig-Funktionen für Implementierungen auch benutzerdefinierte Tsl-Funktionen, die `params` und `body` brauchen (und eigentlich auch noch den definierenden Kontext), zu repräsentieren:

```zig
pub const Tsl = struct {
    ...

    const Value = union(enum) {
        int: i64,
        builtin: *const fn (*Tsl) Error!i64,
        function: struct {
            params: [][]const u8,
            body: [][]const u8,
        },
    };

    bindings: std.StringHashMap(Value),

    ...
}
```

Ich müsste eigentlich das `i64` überall durch `Value` ersetzen, aber das lasse ich erst noch mal weg und konzentriere mich auf die `bindings`, wo die alles entscheidende Funktion jetzt so ausieht:

```zig
    try bindings.put("funktion", Tsl.Value{
        .builtin = struct {
            fn doFunc(t: *Tsl) !i64 {
                const name = t.next();
                const params = try t.evalBlock();
                const body = try t.evalBlock();
                try t.bindings.put(name, Tsl.Value{ .function = .{
                    .params = params,
                    .body = body,
                } });
                return 0;
            }
        }.doFunc,
    });
```

Die neue `eval`-Methode sieht jetzt so aus:

```zig
    fn eval(self: *Tsl) Error!i64 {
        const word = self.next();
        if (word.len == 0) return Error.EndOfInput;
        if (self.bindings.get(word)) |value| {
            return switch (value) {
                .int => value.int,
                .builtin => value.builtin(self),
                .function => {
                    var tsl = Tsl{
                        .bindings = self.bindings,
                        .words = value.function.body,
                    };
                    for (value.function.params) |param| {
                        var arg = Value{ .int = try self.eval() };
                        try tsl.bindings.put(param, arg);
                    }
                    return tsl.evalAll();
                },
            };
        }
        return std.fmt.parseInt(i64, word, 10) catch Error.UnknownWord;
    }
```

Mit einem `switch` unterscheide ich die verschiedenen Fälle: Zahlen gebe ich einfach zurück, Zig-Funktionen rufe ich wie bisher auf und meine benutzerdefinierten Funktionen implementiere ich jetzt direkt hier: Ich brauche eine neue Ausführungsumgebung `tsl`, in der ich dann alle Parameter setze und schließlich den Rumpf der Funktion ausführe (Ja, ich weiß, ich müsste hier ein neues `bindings`-Objekt erzeugen, siehe unten).

Merkwürdigerweise funktioniert das und ich erhalte nach einem `zig build run` die Ausgabe `6227020800`, was passen könnte, wie Copilot meint.

### Fibonacci deckt es auf.

Wenn ich nun dies ausführen will

    funktion fibonacci [n] [
        wenn kleiner? n 3 [1] [
            addiere fibonacci subtrahiere n 1 fibonacci subtrahiere n 2
        ]
    ]
    drucke fibonacci 5

erkenne ich, dass ich meine Variable `n` überschreibe, weil ich immer die selben `bindings` benutze. Und wenn ich korrekt neue `bindings` erzeuge (wie ich eigentlich auch wollte – das war ein Copilot-Fehler, den ich einfach übernommen hatte) finde ich die eingebauten Implementierungen nicht mehr, weil ich keine Vererbung zwischen den Kontexten habe.

Ich füge daher dies hinzu:

```zig
pub const Tsl = struct {
    ...

    allocator: std.mem.Allocator,
    parent: *Tsl,

    ...

    fn init(parent: ?*Tsl, allocator: std.mem.Allocator) Tsl {
        return Tsl{
            .allocator = allocator,
            .parent = parent,
            .bindings = std.StringHashMap(Value).init(allocator),
            .words = &[_][]const u8{},
        };
    }

    ...

    fn get(self: *Tsl, name: []const u8) ?Value {
        if (self.bindings.get(name)) |value| return value;
        if (self.parent) |parent| return parent.get(name);
        return null;
    }

    ...
}
```

Danach ändere ich `self.bindings.get` in `self.get`, fixe die restlichen Fehler, wo ich `Tsl` jetzt mit `parent` und `allocator` initialisieren muss und, voila, ich kann die Fibonacci-Zahl von 20 als `6765` korrekt bestimmen… 

Größere Zahlen gehen nicht, da das Unmengen an Speicher verbraucht. Die `102334155` von `fib(40)` gibt ja auch an, wie viele rekursive Aufrufe ich brauche. Und mein Interpreter gibt niemals Speicher frei und ich weiß nicht, ob ich nicht aus Versehen, meine Wörter immer kopiere. Bei 80 GB RAM ist da irgendwann Schluss. Das kann nicht richtig sein!

### Fazit

Ich vermisse _Closures_. Ich verstehe, warum Zig sie nicht hat. Ohne automatische Speicherveraltung kann man den äußeren Kontext kaum verwalten. Ich verstehe auch, warum sie die manuelle Speicherverwaltung so explizit machen, aber es wirkt dadurch ziemlich mühsam. Ich müsste für meine Scriptsprache eine eigene automatische Speicherverwaltung implementieren. Das ist aufwendiger als alles, woraus die Sprache bislang besteht. Es hat mich außerdem mehr als 4h gekostet, einzusehen, dass Zig wirklich nicht kann, was ich will und ich einen anderen Ansatz (die _tagged union_) brauche.

Die explizite Fehlerbehandlung mittels _error union_ ist okay und das `try`, das im Prinzip einem "wenn Fehler, dann jetzt return mit dem Fehler" entspricht, ist erstaunlich okay. Auch das `catch` ist bequem zu benutzen. Das ist besser als bei Go.

Bis ich die Unittests schrieb, für die ich ein `deinit` bzw. `free` hinzufügen müsste, weil der `std.testing.Allocator` sonst _leaks_ gemeldet hat, hatte `fibonacci 40` gigabyte-weise RAM verbraucht. Nun läuft das (wenn auch wie erwartet langsam) in unter 1 MB ab.

Die integrierbaren _unit tests_ sind nett, aber ich könnte auch ohne Leben und tatsächlich eher eigene Dateien vorziehen, auch wenn man dann natürlich nur das öffentliche API und nicht die privaten Funktionen testen kann.

Copilot hat geholfen, mir Code vorzuschlagen, meist hat er in Details aber nicht gestimmt und ich brauchte immer _trail and error_ um die Typen kompatibel zueinander zu machen. Ungewohnt primitiv ist, dass die IDE kaum Fehler meldet und man erst `zig build` aufrufen muss, was wiederum den Fehler in ziemlich Müllausgaben verbirgt. Das nervt.

### CG-Überlegungen

Eine TSL-Funktion muss ihren definierenden Kontext kennen und dieser kennt seinen übergeordneten Kontext und auch _bindings_, in denen weitere TSL-Funktionen enthalten sein können, die weitere Kontexte kennen. Ich kann einen Kontext damit erst dann frei geben, wenn er nirgends referenziert wird.

Aktuell ist er ein _record_ bestehend aus der Referenz auf den übergeordneten Kontext, der Referenz auf die manuell angelegten _bindings_, der Referenz auf die Wörter sowie einem Index in diese. Freigeben muss ich die _bindings_.

Wenn ich eine globale Liste aller `Tsl`-Strukturen verwalte, könnte ich mitzählen, wie häufig eine Struktur referenziert wird. Allerdings kann ich Zyklen erzeugen, d.h. ich brauche eine "echte" _garbage collection_ nicht nur _reference counting_. Am einfachsten ist der _mark & sweep_ Algorithmus zu implementieren.

Hier ist der ungetestete Version einer Verwaltung `P` für Werte von `V`: Ich nutze aus, dass `Tsl` einen Zeiger auf seinen Vorgänger hat, den ich als Zeiger für eine _free list_ missbrauchen kann, wenn das Objekt eh nicht benutzt wird.

```zig
const V = struct {
    parent: ?*V,
    bindings: std.StringHashMap(V),
    mark: bool,
};

const P = struct {
    allocator: std.mem.Allocator,
    n: usize,
    vs: [*]V,
    free: ?*V,

    fn init(allocator: std.mem.Allocator, n: usize) P {
        // allocate pool
        const vs = allocator.alloc(V, n);

        // build free list
        var i: usize = 1;
        while (i < n) : (i += 1) {
            vs[i - 1].parent = &vs[i];
        }

        // initialize everything
        return P{
            .allocator = allocator,
            .n = n,
            .vs = vs,
            .free = &vs[0],
        };
    }

    fn deinit(p: *P) void {
        p.allocator.free(p.vs);
        p.n = 0;
        p.vs = &[_]V{};
        p.free = null;
    }

    fn create(p: *P) !*V {
        if (p.free) |v| {
            p.free = v.parent;
            v.parent = null;
            v.bindings = std.StringHashMap(V).init(p.allocator);
            return p;
        }
        return error.OutOfMemory;
    }

    fn destroy(p: P, v: *V) void {
        // make sure it's not already freed
        std.debug.assert(blk: {
            var f = p.free;
            while (f) |ff| : (f = ff.parent) {
                if (f == v) break :blk false;
            }
            break :blk true;
        });
        v.bindings.deinit();
        v.parent = p.free;
        p.free = v;
    }

    fn mark(p: *P, v: ?*V) void {
        if (v == null) return;
        if (v.mark) return;
        v.mark = true;
        for (v.bindings) |entry| {
            p.mark(entry.value_ptr);
        }
        if (v.parent) |parent| p.mark(parent);
    }

    fn gc(p: *P) void {
        // mark everything in the free list
        // (could be p.mark(p.free) but would be horrible recursive)
        var f = p.free;
        while (f) |v| : (f = v.parent) {
            v.mark = true;
        }

        // mark roots
        // (currently, there's just one)
        // (this is recursive but there's a non-recursive algorithm)
        p.mark(&p.vs[0]);

        // now check for unmarked values to destroy them
        // (could use pointers instead of indices)
        var i: usize = 0;
        while (i < p.n) : (i += 1) {
            const v = p.vs[i];
            if (v.mark) {
                v.mark = false;
            } else {
                p.destroy(v);
            }
        }
    }
};
```

Das sind mehr als 100 Zeilen und recht aufwendig, insbesondere glaube ich, dass das nicht reicht, denn wenn ich ein `V` mit `create` erzeuge, aber nirgends für `P` erreichbar ablege, wird es sofort wieder freigegeben. Ich müsste dazu den System-Stack durchsuchen können (wie es konservative GC-Algorithmen für C machen) und dabei hoffen, dass nichts einfach nur in einem Prozessor-Register gehalten wird (das verhindert man in C durch einen expliziten `longjmp`, wenn ich das von vor 30 Jahren richtig erinnere). Alles in allem daher noch unbefriedigend.

## RegExp

Ich habe daher das Thema gewechselt und geschaut, wie man C Bibliotheken einbinden kann. Am Beispiel der PCRE-Bibliothek (perl compatible regular expressions) reicht ein:

```zig
const pcre2 = @cImport(@cInclude("pcre2posix.h"));
```

Man muß dem `zig` Kommando dann aber noch sagen, wo er die Sachen findet, z.B.

    zig test -I/usr/local/include -lpcre2-posix src/re.zig

Die Schwierigkeit ist jetzt, das etwas krude C-API zu benutzen und dabei die Typen richtig zu konvertieren. Ich muss `regcomp` aufrufen und dabei ein `regex_t`-Dingens initialisieren, dann kann ich `regexec` aufrufen und muss am Schluss `regfree` aufrufen. Das API will C-Strings haben, die bekanntlich null-terminiert sind. Insgeheim sind das Zig-String-Literale ebenfalls. Der Typ `[5:0]const u8` wurde es deutlich machen, dass dies ein 5-Byte-String mit einer 0 an der 6. Position ist. Das API nutzt `[*c]const u8`, was irgendwie ähnlich genug ist. Da gar nicht so klar ist, wie ein `regex_t` überhaupt aufgebaut ist, kann man den mit `= undefined` auch undefiniert lassen. Es wäre dann ein implementierungsfehler mit undefinierten Laufzeitverhalten, da vor der Initialisierung drauf zu zugreifen.

```zig
var regex: pcre2.regex_t = undefined;
if (pcre2.regcomp(&regex, "\\d+", 0) != 0) {
    return error{InvalidPattern};
}
defer pcre2.regfree(&regex);
var match = pcre2.regexec(&regex, "42", 0, null, 0) != 0;
```

Bei `regexec` könnte man noch ein Array von `regmatch_t`-Strukturen übergeben (und dessen Länge), wenn man _caputure groups_ unterstützen will. Die letzte 0 in beiden _calls_ sind Flags.

Ich habe bestimmt zwei Stunden gebastelt, um ein schönes API hinzubekommen und das zu lernen, was ich jetzt so eben mal beschrieben habe. Insbesondere ist ein Problem, das obiges nur mit String-Literalen funktioniert, was praxisfern ist und man ansonsten kopieren und eine 0 hinzufügen müsste, was wieder einen `Allocator` braucht – oder schlussendlich lernen, dass man die PCRE-Bibliothek auch in einem Modus benutzen kann, wo man String-Längen mit übergeben kann. Das erschien mir der beste Weg.

Erkenntnis ist aber, dass die Interaktion mit C dadurch, das _slices_ normalerweise nicht nullterminiert sind, etwas erschwert wird und man hoffen sollte, dass es passende APIs gibt.

## SDL

Ich habe auch noch versucht, die SDL-Bibliothek zu benutzen und da funktioniert das Beispiel auf anhieb. Das war nett. Hier könnte man jetzt auch wieder anfangen, ein Zig-kompatibles API über das C-API zu setzen, damit man das schöner benutzen kann und natürlich haben Leute das auch schon gemacht. Das kann man aber nicht so einfach finden und nutzen, da es noch keinen offiziellen Package-Manager inklusive zentralem Repository gibt.

## Parser-Kombinator

In der Theorie ist ein _Parser_ eine Funktion, die eine _Eingabe_ entweder (teilweise) _akzeptiert_ und ein _Ergebnis_ zusammen mit der restlichen Eingabe liefert oder mit einem _Fehler_ _zurückweist_. Es gibt dann primitive Parser, die z.B. ein bestimmtes einzelnes Element der Eingabe akzeptieren und komplexe Parser, die andere Parser _kombinieren_, etwa ein Parser, der entweder den einen oder den anderen Parser nimmt, beide nacheinander ausführt oder einen Parser solange nacheinander ausführt, wie er die Eingabe akzeptiert. Dies sind die selben Bausteine, aus denen kontextfreie Grammatiken aufgebaut sind.

In Dart könnte ein Parser so definiert werden:

```dart
sealed class Result<T, I> {...}
class Success<T, I> extends Result<T, I> { ... }
class Failure<T, I> extends Result<T, I> { ... }

typedef Parser<T, I> = Result<T, I> Function(I);

Parser<String, String> char(String c) {
  return (input) {
    if (input.isNotEmpty && input[0] == c) {
      return Success(c, input.substring(1));
    }
    return Failure("expected $c");
  };
}

Parser<T, I> alt<T, I>(Parser<T, I> p1, Parser<T, I> p2) {
  return (input) => switch (p1(input)) {
        Success(:var value, :var input) => Success(value, input),
        Failure(message: var message1) => switch (p2(input)) {
            Success(:var value, :var input) => Success(value, input),
            Failure(message: var message2) => Failure('$message1 or $message2'),
          },
      };
}

Parser<(T1, T2), I> seq<T1, T2, I>(Parser<T1, I> p1, Parser<T2, I> p2) {
  return (input) => switch (p1(input)) {
        Success(value: var value1, :var input) => switch (p2(input)) {
            Success(value: var value2, :var input) => Success((value1, value2), input),
            Failure(message: var message) => Failure(message),
          },
        Failure(message: var message) => Failure(message),
      };
}

Parser<List<T>, I> rep<T, I>(Parser<T, I> p) {
  return (input) {
    final result = <T>[];
    while (true) {
      final r = p(input);
      if (r is Success<T, I>) {
        result.add(r.value);
        input = r.input;
      } else {
        return Success(result, input);
      }
    }
  };
}
```

In Zig gibt es weniger generische Typen noch Klassen oder Vererbung, aber man kann zur Laufzeit neue Strukturen und damit auch neue Typen erzeugen.

### Stack<T>

Hier ist ein Beispiel für einen `Stack`:

```zig
pub fn Stack(comptime T: type, comptime n: comptime_int) type {
    return struct {
        elements: [n]T = undefined,
        index: usize = 0,

        const Self = @This();

        pub fn push(self: *Self, value: T) void {
            self.elements[self.index] = value;
            self.index += 1;
        }

        pub fn pop(self: *Self) T {
            self.index -= 1;
            return self.elements[self.index];
        }
    };
}
```

Die Funktion `Stack` erzeugt nun einen konkreten Typ, z.B. `Stack(u16, 128)` und den kann ich dann initialisieren und nutzen wie jeden anderen Typ auch:

```zig
var stack = Stack(u16, 128){};
stack.push(3);
stack.push(4);
stack.pop(); // 4
stack.pop(); // 3
```

### Result<T, I>

Das gleiche Prinzip kann ich nun nutzen, um einen `Result`-Type basierend auf einer _tagged union_ zu erzeugen, bei dem ich `T` und `I` _generisch_ mache:

```zig
fn Result(comptime T: type, comptime I: type) type {
    return union(enum) {
        success: struct {
            value: T,
            rest: I,
        },
        failure: str,
    };
}
```

### Parser<T, I>

Der Parser ist aber komplizierter, weil ich weder _Closures_ noch Vererbung habe. Ich muss die Funktion, die den Parser implementiert, daher als `struct` übergeben und ich habe `usingnamespace` gefunden, was eine Struktur in eine andere einbettet.

```zig
pub fn Parser(comptime P: type) type {
    return struct {
        const Self = @This();

        pub usingnamespace P;
    };
}
```

Was man jetzt noch machen will: Zur Übersetzungszeit nachgucken, ob `P` wohl eine Struktur ist, die die eine `parse` Funktion hat, die ein `Result(T, I)` zurückliefert und selbst einen Parameter hat, der ein `I` ist. Mit `@field(P, "parse")` kommt man z.B. an die Funktion, mit `@typeInfo` kann man gucken, dass das wirklich eine Funktion ist und dann mit `return_type` und `param[0]` auf eben erwähnten Typen zugreifen und dann prüfen. Damit ich die beiden Typen von `Result` kenne, muss ich die so exportieren:

```zig
fn Result(comptime _T: type, comptime _I: type) type {
    return union(enum) {
        const T = _T;
        const I = _I;
        ...
    }
}
```

Und dann kann ich das hier machen:

```zig
pub fn Parser(comptime P: type) type {
    switch (@typeInfo(@TypeOf(@field(P, "parse")))) {
        .Fn => |f| {
            if (f.params[0].type.? != f.return_type.?.I) {
                @panic("parse function has wrong signature");
            }
        },
        else => unreachable,
    }
    ...
}
```

Als nächstes kann ich dann eine Funktion `Char` schreiben, mit der ich einen Parser erzeugen kann, der ein einzelnes Zeichen parsen kann:

```zig
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
```

Für `alt`, `seq` und `rep` muss ich die Typen `T` und `I` kennen, was ich mir über das `Result` holen kann, was ich eben garede schon mühsam berechnet habe. Daher ergänze ich noch:

```zig
pub fn Parser(comptime P: type) type {
    ...

    return struct {
        const Result = (switch (@typeInfo(@TypeOf(@field(P, "parse")))) {
            .Fn => |f| f.return_type.?,
            else => unreachable,
        });

        ...
    }
}
```

Jetzt kann ich mir dies hier zusammenstückeln, leider völlig ohne _code completion_, weil die IDE nicht wissen kann, was der Compiler da nachher ausrechnet, **bevor** er die Typprüfung macht. Das komplizierteste hier ist, dass ich zwei Strings kombinieren will, was ich nicht kann, ohne einen `Allocator`, den ich jetzt aber nicht einführen will, daher nutze ich einen statischen Buffer, der nicht lange genug lebt. Aber egal.

```zig
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
```

Das `Seq` und `Rep` könnt ihr jetzt ja selbst bauen. Na gut, hier noch das `Rep`, das wieder einen `Allocator` bräuchte, da ich die Ergebnisse akkumulieren will.

```zig
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
```

Jetzt kann ich mit einem `{a|b}`-Parser einen String teilweise einlesen:

```zig
pub fn main() void {
    const Ca = Char('a');
    const Cb = Char('b');
    const P = Rep(Alt(Ca, Cb));
    var r = P.Self.parse("abbc");
    std.debug.print("{}\n", .{r});
}
```