#!/usr/bin/env dub
/+ dub.sdl:
   dependency "d2" version="~master"
+/

import std;

struct SensorEvent
{
    SysTime timestamp;
    string sensor;
    double value;
}

// Parse timestamp like "2025-05-23-14-30-45"
SysTime parseSensorTimestamp(string ts)
{
    // Convert "yyyy-mm-dd-h-m-s" → "yyyy-mm-dd h:m:s"
    string fixed = ts.replace("-", ":", 11);  // Only replace after date
    return SysTime.fromISOExtString(fixed ~ "Z"); // Assume UTC or adjust as needed
}

void main(string[] args)
{
    string folder = args.length > 1 ? args[1] : ".";  // Default to current dir

    writeln("Scanning folder: ", folder);

    // === 1. Find and sort all daily JSON files ===
    auto jsonFiles = dirEntries(folder, SpanMode.shallow)
        .filter!(de => de.isFile)
        .filter!(de => de.name.endsWith(".json"))
        .filter!(de => de.baseName.matchFirst(r"^\d{4}-\d{2}-\d{2}\.json$"))  // yyyy-mm-dd.json
        .array;

    // Sort chronologically by filename
    jsonFiles.sort!((a, b) => a.baseName < b.baseName);

    writeln("Found ", jsonFiles.length, " daily files");

    // === 2. Pipeline: Process all events across all files ===
    SensorEvent[] allEvents = jsonFiles
        .map!((DirEntry de) {
            try
            {
                string content = readText(de.name);
                JSONValue root = parseJSON(content);
                return root.array;  // Assume each file is a JSON array
            }
            catch (Exception e)
            {
                writeln("Error reading ", de.baseName, ": ", e.msg);
                return JSONValue[].init;
            }
        })
        .joiner                              // Flatten all arrays into one range
        .map!((JSONValue j) {
            try
            {
                return SensorEvent(
                    parseSensorTimestamp(j["timestamp"].str),
                    j["sensor"].str,
                    j["value"].floating
                );
            }
            catch (Exception e)
            {
                // Skip malformed events
                return SensorEvent.init;
            }
        })
        .filter!(e => e.timestamp != SysTime.init)  // Remove invalid events
        .array;  // Materialize (or keep lazy for very large datasets)

    writeln("Total valid sensor events: ", allEvents.length);

    // === 3. Example analyses (pipelined) ===

    // Events per sensor
    auto bySensor = allEvents
        .groupBy!((e) => e.sensor)
        .map!(g => tuple(g[0], g.count))
        .array
        .sort!((a, b) => a[1] > b[1]);  // Most active first

    writeln("\nEvents per sensor:");
    foreach (ref s; bySensor)
        writefln("  %s: %d events", s[0], s[1]);

    // Daily summary
    auto daily = allEvents
        .groupBy!(e => e.timestamp.date)
        .map!(g => tuple(g[0], g.count, g.map!(e => e.value).mean))
        .array;

    writeln("\nDaily summary:");
    foreach (ref d; daily)
        writefln("  %s: %d events, avg value %.3f", d[0], d[1], d[2]);

    // Example: Find max value per sensor
    auto maxValues = allEvents
        .groupBy!((e) => e.sensor)
        .map!(g => tuple(
            g[0],
            g.maxElement!((a,b) => a.value > b.value).value
        ))
        .array;

    writeln("\nMax value per sensor:");
    foreach (ref m; maxValues)
        writefln("  %s: %.3f", m[0], m[1]);
}