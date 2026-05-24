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

SysTime parseSensorTimestamp(string ts)
{
    // "2025-05-23-14-30-45" → "2025-05-23T14:30:45Z"
    string fixed = ts[0..10] ~ "T" ~ ts[11..$].replace("-", ":");
    return SysTime.fromISOExtString(fixed ~ "Z");
}

void main(string[] args)
{
    string folder = args.length > 1 ? args[1] : ".";

    // ==================== 1. LOAD & PARSE ALL DATA ====================
    auto jsonFiles = dirEntries(folder, SpanMode.shallow)
        .filter!(de => de.isFile && de.baseName.matchFirst(r"^\d{4}-\d{2}-\d{2}\.json$"))
        .array.sort!((a, b) => a.baseName < b.baseName);

    SensorEvent[] allEvents = jsonFiles
        .map!((de) {
            try {
                auto root = parseJSON(readText(de.name));
                return root.array;
            } catch (Exception) { return JSONValue[].init; }
        })
        .joiner
        .map!((j) {
            try {
                return SensorEvent(
                    parseSensorTimestamp(j["timestamp"].str),
                    j["sensor"].str,
                    j["value"].floating
                );
            } catch (Exception) { return SensorEvent.init; }
        })
        .filter!(e => e.timestamp != SysTime.init)
        .array;

    // Sort chronologically (critical for time series)
    allEvents.sort!((a, b) => a.timestamp < b.timestamp);

    writeln("Loaded ", allEvents.length, " sensor events from ", jsonFiles.length, " days");

    // ==================== 2. TIME SERIES ANALYSIS ====================

    // Group by sensor
    auto sensors = allEvents.groupBy!((e) => e.sensor);

    foreach (string sensorName, auto events; sensors)
    {
        writeln("\n=== Time Series Analysis: ", sensorName, " ===");
        auto ts = events.array;  // events for this sensor (already sorted)

        if (ts.length < 2) {
            writeln("  Not enough data");
            continue;
        }

        // Basic statistics
        auto values = ts.map!(e => e.value);
        writefln("  Total readings: %d", ts.length);
        writefln("  Date range: %s → %s", ts.front.timestamp.date, ts.back.timestamp.date);
        writefln("  Mean: %.4f", values.mean);
        writefln("  StdDev: %.4f", values.stdDev);
        writefln("  Min: %.4f | Max: %.4f", values.minElement, values.maxElement);

        // === Rolling / Moving Average (window = 10 readings) ===
        auto movingAvg = ts
            .slide(10)                    // sliding window of 10 points
            .map!(window => window.map!(e => e.value).mean)
            .array;

        writeln("  Moving Average (last 10 readings): ", movingAvg[$-5..$].map!(x => format("%.3f", x)).join(" "));

        // === Hourly Aggregation ===
        auto hourly = ts
            .groupBy!(e => e.timestamp.toISOExtString()[0..13])  // group by hour
            .map!(g => Tuple!(string, size_t, double)(
                g[0],
                g.count,
                g.map!(e => e.value).mean
            ))
            .array;

        writeln("  Hourly average samples: ", hourly.length);

        // === Daily Aggregation ===
        auto dailyStats = ts
            .groupBy!(e => e.timestamp.date)
            .map!(day => Tuple!(Date, double, double, double)(
                day[0],
                day.map!(e => e.value).mean,
                day.map!(e => e.value).minElement,
                day.map!(e => e.value).maxElement
            ))
            .array;

        writeln("\n  Daily Summary (last 5 days):");
        foreach (ref d; dailyStats[$-5..$])
            writefln("    %s: avg=%.3f  min=%.3f  max=%.3f", d[0], d[1], d[2], d[3]);

        // === Simple Peak Detection (value > both neighbors) ===
        size_t peaks = 0;
        for (size_t i = 1; i < ts.length - 1; ++i)
        {
            if (ts[i].value > ts[i-1].value && ts[i].value > ts[i+1].value)
                peaks++;
        }
        writefln("  Detected peaks: %d", peaks);

        // === Data gaps check (more than 2 hours between readings) ===
        size_t gaps = 0;
        for (size_t i = 1; i < ts.length; ++i)
        {
            Duration diff = ts[i].timestamp - ts[i-1].timestamp;
            if (diff > 2.hours)
                gaps++;
        }
        writefln("  Significant gaps (>2h): %d", gaps);
    }

    // ==================== 3. OVERALL CROSS-SENSOR SUMMARY ====================
    writeln("\n=== Overall Time Series Summary ===");
    auto overallDaily = allEvents
        .groupBy!(e => e.timestamp.date)
        .map!(day => tuple(day[0], day.count))
        .array;

    writeln("Daily event counts:");
    foreach (ref d; overallDaily)
        writefln("  %s → %d events", d[0], d[1]);
}