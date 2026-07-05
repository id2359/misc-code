// orac3.ck
// Alarm-panel variant of the vintage computer ambience

Gain mix => Dyno limiter => dac;
0.8 => mix.gain;
0.9 => limiter.thresh;

PulseOsc sirenA => LPF sirenAFilt => DelayA sirenAEcho => Pan2 sirenAPan => mix;
PulseOsc sirenB => LPF sirenBFilt => DelayA sirenBEcho => Pan2 sirenBPan => mix;
SqrOsc alarm => BPF alarmBand => NRev alarmRev => Pan2 alarmPan => mix;
SawOsc scanner => LPF scannerFilt => Pan2 scannerPan => mix;
Noise noiseFloor => HPF staticHPF => Gain staticGain => mix;

0.16 => sirenA.gain;
0.12 => sirenB.gain;
0.08 => alarm.gain;
0.05 => scanner.gain;
0.01 => staticGain.gain;

1800 => sirenAFilt.freq;
2.4 => sirenAFilt.Q;
1500 => sirenBFilt.freq;
2.0 => sirenBFilt.Q;
2200 => alarmBand.freq;
6.0 => alarmBand.Q;
900 => scannerFilt.freq;
1.2 => scannerFilt.Q;
3200 => staticHPF.freq;

220::ms => sirenAEcho.max => sirenAEcho.delay;
170::ms => sirenBEcho.max => sirenBEcho.delay;
0.28 => sirenAEcho.gain;
0.2 => sirenBEcho.gain;
0.07 => alarmRev.mix;

-0.55 => sirenAPan.pan;
0.5 => sirenBPan.pan;
0.0 => alarmPan.pan;
0.15 => scannerPan.pan;

[84, 91, 88, 96, 93, 89] @=> int alertNotes[];
[0.08, 0.14, 0.22, 0.1, 0.18, 0.12] @=> float pulseWidths[];

fun void alertClusterA()
{
    0 => int i;

    while (true)
    {
        Std.mtof(alertNotes[i % alertNotes.cap()]) => sirenA.freq;
        pulseWidths[i % pulseWidths.cap()] => sirenA.width;
        1200 + (i % 4) * 250 => sirenAFilt.freq;
        1 => sirenA.op;
        45::ms => now;
        0 => sirenA.op;
        (90 + (i % 3) * 25)::ms => now;
        i++;
    }
}

fun void alertClusterB()
{
    0 => int i;

    while (true)
    {
        Std.mtof(alertNotes[(i * 2 + 1) % alertNotes.cap()] - 12) => sirenB.freq;
        0.35 + 0.2 * Math.fabs(Math.sin(i * 0.45)) => sirenB.width;
        1000 + (i % 5) * 180 => sirenBFilt.freq;
        1 => sirenB.op;
        30::ms => now;
        0 => sirenB.op;
        (140 + (i % 4) * 40)::ms => now;
        i++;
    }
}

fun void warningTone()
{
    while (true)
    {
        Std.mtof(72) => alarm.freq;
        1 => alarm.op;
        120::ms => now;
        0 => alarm.op;
        80::ms => now;

        Std.mtof(79) => alarm.freq;
        1 => alarm.op;
        120::ms => now;
        0 => alarm.op;
        600::ms => now;
    }
}

fun void scannerSweep()
{
    while (true)
    {
        for (0 => int i; i < 10; i++)
        {
            Std.mtof(48 + i) => scanner.freq;
            700 + i * 140 => scannerFilt.freq;
            80::ms => now;
        }

        for (9 => int i; i >= 0; i--)
        {
            Std.mtof(48 + i) => scanner.freq;
            scannerFilt.freq() - 110 => scannerFilt.freq;
            80::ms => now;
        }
    }
}

fun void staticDrift()
{
    while (true)
    {
        2800 + Math.random2f(0, 2200) => staticHPF.freq;
        0.006 + Math.random2f(0.0, 0.01) => staticGain.gain;
        150::ms => now;
    }
}

spork ~ alertClusterA();
spork ~ alertClusterB();
spork ~ warningTone();
spork ~ scannerSweep();
spork ~ staticDrift();

18::second => now;
