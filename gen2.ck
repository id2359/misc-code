// orac2.ck
// Vintage computer beep/blip ambience for a sci-fi background

Gain mix => Dyno limiter => dac;
0.85 => mix.gain;
0.92 => limiter.thresh;

PulseOsc toneA => LPF filtA => DelayA echoA => Pan2 panA => mix;
PulseOsc toneB => LPF filtB => DelayA echoB => Pan2 panB => mix;
TriOsc bed => LPF bedFilt => NRev bedRev => Pan2 bedPan => mix;
Noise hiss => HPF hissHPF => Gain hissGain => mix;

0.18 => toneA.gain;
0.11 => toneB.gain;
0.06 => bed.gain;
0.012 => hissGain.gain;

1400 => filtA.freq;
2.2 => filtA.Q;
1100 => filtB.freq;
1.8 => filtB.Q;
900 => bedFilt.freq;
0.9 => bedFilt.Q;
3000 => hissHPF.freq;

320::ms => echoA.max => echoA.delay;
260::ms => echoB.max => echoB.delay;
0.22 => echoA.gain;
0.18 => echoB.gain;

0.09 => bedRev.mix;
-0.45 => panA.pan;
0.38 => panB.pan;
0.0 => bedPan.pan;

[72, 79, 76, 84, 81, 77, 74, 86] @=> int beepScale[];
[0.08, 0.12, 0.18, 0.09, 0.14, 0.11, 0.16, 0.1] @=> float widths[];

fun void slowBed()
{
    52.0 => bed.freq;

    while (true)
    {
        for (0 => int i; i < 8; i++)
        {
            46 + i * 2 => int midi;
            Std.mtof(midi) => bed.freq;
            500 + i * 70 => bedFilt.freq;
            0.04 + 0.01 * Math.sin(now / second) => bed.gain;
            800::ms => now;
        }
    }
}

fun void telemetryA()
{
    0 => int i;

    while (true)
    {
        Std.mtof(beepScale[i % beepScale.cap()]) => toneA.freq;
        widths[i % widths.cap()] => toneA.width;
        900 + (i % 5) * 180 => filtA.freq;
        0.15 + 0.08 * Math.sin(i * 0.4) => toneA.gain;
        1 => toneA.op;
        70::ms => now;
        0 => toneA.op;
        (140 + (i % 4) * 40)::ms => now;
        i++;
    }
}

fun void telemetryB()
{
    0 => int i;

    while (true)
    {
        Std.mtof(beepScale[(i * 3 + 2) % beepScale.cap()] - 12) => toneB.freq;
        0.45 + 0.15 * Math.sin(i * 0.3) => toneB.width;
        700 + (i % 6) * 110 => filtB.freq;
        0.07 + 0.05 * Math.fabs(Math.sin(i * 0.27)) => toneB.gain;
        1 => toneB.op;
        35::ms => now;
        0 => toneB.op;
        (260 + (i % 5) * 55)::ms => now;
        i++;
    }
}

fun void hissDrift()
{
    while (true)
    {
        2500 + Math.random2f(0, 2500) => hissHPF.freq;
        0.008 + Math.random2f(0.0, 0.008) => hissGain.gain;
        180::ms => now;
    }
}

spork ~ slowBed();
spork ~ telemetryA();
spork ~ telemetryB();
spork ~ hissDrift();

60::second => now;
