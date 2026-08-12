/**
 * dbills - a small command-line bill tracker backed by a bills.json file.
 *
 * Usage:
 *   dbills add <name> <amount> <due-date YYYY-MM-DD> [category]
 *   dbills list [all|paid|unpaid|overdue]
 *   dbills pay <id>
 *   dbills unpay <id>
 *   dbills remove <id>
 *   dbills edit <id> <name|amount|due|category> <value>
 *   dbills total [all|paid|unpaid]
 *   dbills help
 *
 * Bills are stored as JSON in bills.json, located next to wherever the
 * command is run from (i.e. the current working directory).
 *
 * Commands, list/total filters, and editable fields are modeled as
 * algebraic data types (D's std.sumtype.SumType) rather than raw strings.
 * Parsing turns CLI text into one of these ADTs up front, and every
 * subsequent decision is made via exhaustive `match!` pattern matching,
 * so the compiler guarantees every variant is handled.
 */

import std.stdio;
import std.json;
import std.file;
import std.conv;
import std.string;
import std.algorithm;
import std.array;
import std.datetime.date;
import std.datetime.systime;
import std.format;
import std.exception;
import std.sumtype;

immutable string dataFile = "bills.json";

struct Bill {
    int id;
    string name;
    double amount;
    string dueDate; // ISO-8601 "YYYY-MM-DD"
    bool paid;
    string category;
}

// ---------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------

/// A user-facing CLI error; its message is printed as-is (no "Error:" prefix).
class CliError : Exception {
    this(string msg) { super(msg); }
}

/// Like CliError, but also triggers the full usage banner.
class UnknownCommandError : CliError {
    this(string msg) { super(msg); }
}

// ---------------------------------------------------------------------
// ADTs: filters
// ---------------------------------------------------------------------

struct FilterAll {}
struct FilterPaid {}
struct FilterUnpaid {}
struct FilterOverdue {}

/// `dbills list` accepts all four filter variants.
alias ListFilter = SumType!(FilterAll, FilterPaid, FilterUnpaid, FilterOverdue);

/// `dbills total` intentionally has no "overdue" variant.
alias TotalFilter = SumType!(FilterAll, FilterPaid, FilterUnpaid);

ListFilter parseListFilter(string s) {
    switch (s) {
        case "all":     return ListFilter(FilterAll());
        case "paid":    return ListFilter(FilterPaid());
        case "unpaid":  return ListFilter(FilterUnpaid());
        case "overdue": return ListFilter(FilterOverdue());
        default:
            throw new CliError(format("Unknown filter '%s'. Use all, paid, unpaid, or overdue.", s));
    }
}

TotalFilter parseTotalFilter(string s) {
    switch (s) {
        case "all":    return TotalFilter(FilterAll());
        case "paid":   return TotalFilter(FilterPaid());
        case "unpaid": return TotalFilter(FilterUnpaid());
        default:
            throw new CliError(format("Unknown filter '%s'. Use all, paid, or unpaid.", s));
    }
}

// ---------------------------------------------------------------------
// ADT: editable bill fields (each variant carries its own typed value)
// ---------------------------------------------------------------------

struct EditName     { string value; }
struct EditAmount   { double value; }
struct EditDue      { string value; }
struct EditCategory { string value; }

alias EditField = SumType!(EditName, EditAmount, EditDue, EditCategory);

EditField parseEditField(string field, string value) {
    switch (field) {
        case "name":
            return EditField(EditName(value));
        case "amount":
            double amount;
            try {
                amount = to!double(value);
            } catch (Exception e) {
                throw new CliError(format("Invalid amount: %s", value));
            }
            return EditField(EditAmount(amount));
        case "due":
            if (!isValidDate(value)) {
                throw new CliError(format("Invalid date '%s'; expected format YYYY-MM-DD", value));
            }
            return EditField(EditDue(value));
        case "category":
            return EditField(EditCategory(value));
        default:
            throw new CliError(format("Unknown field '%s'. Use name, amount, due, or category.", field));
    }
}

// ---------------------------------------------------------------------
// ADT: parsed commands (replaces dispatch-by-string + raw string[] args)
// ---------------------------------------------------------------------

struct AddCmd    { string name; double amount; string dueDate; string category; }
struct ListCmd   { ListFilter filter; }
struct PayCmd    { int id; }
struct UnpayCmd  { int id; }
struct RemoveCmd { int id; }
struct EditCmd   { int id; EditField field; }
struct TotalCmd  { TotalFilter filter; }
struct HelpCmd   {}

alias Command = SumType!(AddCmd, ListCmd, PayCmd, UnpayCmd, RemoveCmd, EditCmd, TotalCmd, HelpCmd);

Command parseCommand(string name, string[] args) {
    switch (name) {
        case "add":
            return Command(parseAddCmd(args));
        case "list":
            return Command(ListCmd(parseListFilter(args.length >= 1 ? args[0] : "all")));
        case "pay":
            return Command(PayCmd(parseId(args, "pay")));
        case "unpay":
            return Command(UnpayCmd(parseId(args, "unpay")));
        case "remove", "rm":
            return Command(RemoveCmd(parseId(args, "remove")));
        case "edit":
            return Command(parseEditCmd(args));
        case "total":
            return Command(TotalCmd(parseTotalFilter(args.length >= 1 ? args[0] : "unpaid")));
        case "help", "-h", "--help":
            return Command(HelpCmd());
        default:
            throw new UnknownCommandError(format("Unknown command: %s", name));
    }
}

int parseId(string[] args, string commandName) {
    if (args.length < 1) {
        throw new CliError(format("Usage: dbills %s <id>", commandName));
    }
    return to!int(args[0]);
}

AddCmd parseAddCmd(string[] args) {
    if (args.length < 3) {
        throw new CliError("Usage: dbills add <name> <amount> <due-date YYYY-MM-DD> [category]");
    }

    string name = args[0];
    double amount;
    try {
        amount = to!double(args[1]);
    } catch (Exception e) {
        throw new CliError(format("Invalid amount: %s", args[1]));
    }

    string dueDate = args[2];
    if (!isValidDate(dueDate)) {
        throw new CliError(format("Invalid date '%s'; expected format YYYY-MM-DD", dueDate));
    }

    string category = args.length >= 4 ? args[3] : "";
    return AddCmd(name, amount, dueDate, category);
}

EditCmd parseEditCmd(string[] args) {
    if (args.length < 3) {
        throw new CliError("Usage: dbills edit <id> <name|amount|due|category> <value>");
    }
    int id = to!int(args[0]);
    EditField field = parseEditField(args[1], args[2]);
    return EditCmd(id, field);
}

// ---------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------

int main(string[] args) {
    if (args.length < 2) {
        printUsage();
        return 1;
    }

    try {
        Command command = parseCommand(args[1], args[2 .. $]);
        return runCommand(command);
    } catch (UnknownCommandError e) {
        stderr.writeln(e.msg);
        printUsage();
        return 1;
    } catch (CliError e) {
        stderr.writeln(e.msg);
        return 1;
    } catch (Exception e) {
        stderr.writefln("Error: %s", e.msg);
        return 1;
    }
}

int runCommand(Command command) {
    return command.match!(
        (AddCmd c) => cmdAdd(c),
        (ListCmd c) => cmdList(c),
        (PayCmd c) => cmdSetPaid(c.id, true),
        (UnpayCmd c) => cmdSetPaid(c.id, false),
        (RemoveCmd c) => cmdRemove(c),
        (EditCmd c) => cmdEdit(c),
        (TotalCmd c) => cmdTotal(c),
        (HelpCmd c) {
            printUsage();
            return 0;
        },
    );
}

void printUsage() {
    writeln(`dbills - manage bills in bills.json

Usage:
  dbills add <name> <amount> <due-date YYYY-MM-DD> [category]
  dbills list [all|paid|unpaid|overdue]
  dbills pay <id>
  dbills unpay <id>
  dbills remove <id>
  dbills edit <id> <name|amount|due|category> <value>
  dbills total [all|paid|unpaid]
  dbills help`);
}

// ---------------------------------------------------------------------
// Persistence
// ---------------------------------------------------------------------

Bill[] loadBills() {
    if (!exists(dataFile)) {
        return [];
    }

    string content = readText(dataFile);
    if (content.strip.empty) {
        return [];
    }

    JSONValue json = parseJSON(content);
    Bill[] bills;
    foreach (item; json.array) {
        Bill b;
        b.id = cast(int) item["id"].integer;
        b.name = item["name"].str;
        b.amount = item["amount"].floating;
        b.dueDate = item["dueDate"].str;
        b.paid = item["paid"].type == JSONType.true_;
        b.category = ("category" in item) ? item["category"].str : "";
        bills ~= b;
    }
    return bills;
}

void saveBills(Bill[] bills) {
    JSONValue[] items;
    foreach (b; bills) {
        JSONValue item = [
            "id": JSONValue(b.id),
            "name": JSONValue(b.name),
            "amount": JSONValue(b.amount),
            "dueDate": JSONValue(b.dueDate),
            "paid": JSONValue(b.paid),
            "category": JSONValue(b.category),
        ];
        items ~= item;
    }
    JSONValue json = JSONValue(items);
    std.file.write(dataFile, json.toPrettyString());
}

int nextId(Bill[] bills) {
    int maxId = 0;
    foreach (b; bills) {
        if (b.id > maxId) maxId = b.id;
    }
    return maxId + 1;
}

// ---------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------

int cmdAdd(AddCmd c) {
    Bill[] bills = loadBills();
    Bill b;
    b.id = nextId(bills);
    b.name = c.name;
    b.amount = c.amount;
    b.dueDate = c.dueDate;
    b.paid = false;
    b.category = c.category;
    bills ~= b;
    saveBills(bills);

    writefln("Added bill #%d: %s ($%.2f, due %s)", b.id, b.name, b.amount, b.dueDate);
    return 0;
}

int cmdList(ListCmd c) {
    Bill[] bills = loadBills();
    string today = todayString();

    Bill[] filtered = c.filter.match!(
        (FilterAll _)     => bills,
        (FilterPaid _)    => bills.filter!(b => b.paid).array,
        (FilterUnpaid _)  => bills.filter!(b => !b.paid).array,
        (FilterOverdue _) => bills.filter!(b => !b.paid && b.dueDate < today).array,
    );

    if (filtered.empty) {
        writeln("No bills found.");
        return 0;
    }

    filtered.sort!((a, b) => a.dueDate < b.dueDate);

    writefln("%-4s %-24s %10s  %-10s %-8s %s", "ID", "Name", "Amount", "Due", "Status", "Category");
    writeln("-".replicate(70));
    foreach (b; filtered) {
        string status = b.paid ? "paid" : (b.dueDate < today ? "OVERDUE" : "unpaid");
        writefln("%-4d %-24s %10.2f  %-10s %-8s %s", b.id, b.name, b.amount, b.dueDate, status, b.category);
    }
    return 0;
}

int cmdSetPaid(int id, bool paid) {
    Bill[] bills = loadBills();
    auto idx = bills.countUntil!(b => b.id == id);
    if (idx < 0) {
        stderr.writefln("No bill with id %d", id);
        return 1;
    }

    bills[idx].paid = paid;
    saveBills(bills);
    writefln("Bill #%d (%s) marked as %s", id, bills[idx].name, paid ? "paid" : "unpaid");
    return 0;
}

int cmdRemove(RemoveCmd c) {
    Bill[] bills = loadBills();
    auto idx = bills.countUntil!(b => b.id == c.id);
    if (idx < 0) {
        stderr.writefln("No bill with id %d", c.id);
        return 1;
    }

    string name = bills[idx].name;
    bills = bills.remove(idx);
    saveBills(bills);
    writefln("Removed bill #%d (%s)", c.id, name);
    return 0;
}

int cmdEdit(EditCmd c) {
    Bill[] bills = loadBills();
    auto idx = bills.countUntil!(b => b.id == c.id);
    if (idx < 0) {
        stderr.writefln("No bill with id %d", c.id);
        return 1;
    }

    c.field.match!(
        (EditName f)     { bills[idx].name = f.value; },
        (EditAmount f)   { bills[idx].amount = f.value; },
        (EditDue f)      { bills[idx].dueDate = f.value; },
        (EditCategory f) { bills[idx].category = f.value; },
    );

    saveBills(bills);
    writefln("Updated bill #%d", c.id);
    return 0;
}

int cmdTotal(TotalCmd c) {
    Bill[] bills = loadBills();

    Bill[] filtered = c.filter.match!(
        (FilterAll _)    => bills,
        (FilterPaid _)   => bills.filter!(b => b.paid).array,
        (FilterUnpaid _) => bills.filter!(b => !b.paid).array,
    );

    string label = c.filter.match!(
        (FilterAll _)    => "all",
        (FilterPaid _)   => "paid",
        (FilterUnpaid _) => "unpaid",
    );

    double total = filtered.map!(b => b.amount).sum;
    writefln("Total (%s): $%.2f across %d bill(s)", label, total, filtered.length);
    return 0;
}

// ---------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------

bool isValidDate(string s) {
    try {
        Date.fromISOExtString(s);
        return true;
    } catch (Exception e) {
        return false;
    }
}

string todayString() {
    auto today = cast(Date) Clock.currTime();
    return format("%04d-%02d-%02d", today.year, today.month, today.day);
}
