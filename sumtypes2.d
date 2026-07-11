import std.stdio;
import std.sumtype;
import std.json;
import std.conv;
import std.math;
import std.array;

// ========================
// 1. BASIC ADT: Shape
// ========================
struct Circle { double r; }
struct Rect { double w, h; }
alias Shape = SumType!(Circle, Rect);

double area(Shape s) {
    return s.match!(
        (Circle c) => PI * c.r * c.r,
        (Rect r) => r.w * r.h
    );
}

// ========================
// 2. OPTION: Maybe a value
// ========================
struct None {}
struct Some(T) { T value; }
alias Option(T) = SumType!(None, Some!T);

Option!T some(T)(T v) { return Option!T(Some!T(v)); }
Option!T none(T)() { return Option!T(None()); }

Option!int safeDivide(int a, int b) {
    if (b == 0) return none!int();
    return some(a / b);
}

// ========================
// 3. RESULT: Ok or Err
// ========================
struct Ok(T) { T value; }
struct Err(E) { E error; }
alias Result(T, E) = SumType!(Ok!T, Err!E);

Result!(int, string) parseInt(string s) {
    try {
        return Result!(int, string)(Ok!int(s.to!int));
    } catch (ConvException e) {
        return Result!(int, string)(Err!string("Invalid int: " ~ s));
    }
}

Result!(double, string) safeSqrt(int x) {
    if (x < 0) return Result!(double, string)(Err!string("sqrt of negative"));
    return Result!(double, string)(Ok!double(sqrt(x.to!double)));
}

// Chain Result: parse -> sqrt
Result!(double, string) parseAndSqrt(string s) {
    return parseInt(s).match!(
        (Ok!int ok) => safeSqrt(ok.value),
        (Err!string e) => Result!(double, string)(e)
    );
}

// ========================
// 4. RECURSIVE ADT: JSON-like value
// ========================
struct JsonNull {}
struct JsonBool { bool value; }
struct JsonNum { double value; }
struct JsonStr { string value; }
struct JsonArray { JsonValue[] items; }
struct JsonObject { JsonValue[string] fields; }

alias JsonValue = SumType!(JsonNull, JsonBool, JsonNum, JsonStr, JsonArray, JsonObject);

void printJson(JsonValue j, int indent = 0) {
    auto pad = " ".replicate(indent);
    j.match!(
        (JsonNull _) => write("null"),
        (JsonBool b) => write(b.value),
        (JsonNum n) => write(n.value),
        (JsonStr s) => write(`"`, s.value, `"`),
        (JsonArray a) {
            write("[\n");
            foreach(i, item; a.items) {
                write(pad, " ");
                printJson(item, indent + 2);
                if (i < a.items.length - 1) write(",");
                writeln();
            }
            write(pad, "]");
        },
        (JsonObject o) {
            writeln("{");
            size_t i = 0;
            foreach(k, v; o.fields) {
                write(pad, " ", `"`, k, `": `);
                printJson(v, indent + 2);
                if (i < o.fields.length - 1) write(",");
                writeln();
                i++;
            }
            write(pad, "}");
        }
    );
}

// ========================
// MAIN DEMO
// ========================
void main() {
    writeln("=== 1. SumType ADT ===");
    Shape s1 = Circle(3.0);
    Shape s2 = Rect(4, 5);
    writeln("Circle area: ", area(s1));
    writeln("Rect area: ", area(s2));

    writeln("\n=== 2. Option ===");
    safeDivide(10, 2).match!(
        (Some!int s) => writeln("10/2 = ", s.value),
        (None _) => writeln("Divide by zero")
    );
    safeDivide(10, 0).match!(
        (Some!int s) => writeln("10/0 = ", s.value),
        (None _) => writeln("Divide by zero")
    );

    writeln("\n=== 3. Result ===");
    parseAndSqrt("16").match!(
        (Ok!double ok) => writeln("sqrt(16) = ", ok.value),
        (Err!string e) => writeln("Error: ", e.error)
    );
    parseAndSqrt("-4").match!(
        (Ok!double ok) => writeln("sqrt(-4) = ", ok.value),
        (Err!string e) => writeln("Error: ", e.error)
    );
    parseAndSqrt("abc").match!(
        (Ok!double ok) => writeln("sqrt(abc) = ", ok.value),
        (Err!string e) => writeln("Error: ", e.error)
    );

    writeln("\n=== 4. Recursive ADT ===");
    JsonValue data = JsonObject([
        "name": JsonValue(JsonStr("Dlang")),
        "active": JsonValue(JsonBool(true)),
        "scores": JsonValue(JsonArray([
            JsonValue(JsonNum(90)),
            JsonValue(JsonNum(85))
        ]))
    ]);
    printJson(data);
    writeln();
}