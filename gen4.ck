// orac4.ck
// OOP power plant control panel acoustic environment

class ControlBed
{
    TriOsc tone;
    LPF filt;
    NRev rev;
    Pan2 pan;
    Gain out;
    float level;

    fun void init(Gain bus, float freq, float gainValue, float panValue)
    {
        tone => filt => rev => pan => out => bus;
        gainValue => level;
        gainValue => tone.gain;
        freq => tone.freq;
        700 => filt.freq;
        1.1 => filt.Q;
        0.08 => rev.mix;
        panValue => pan.pan;
        1.0 => out.gain;
    }

    fun void run()
    {
        0 => int step;

        while (true)
        {
            tone.freq() + Math.sin(step * 0.07) * 4 => tone.freq;
            620 + 180 * Math.fabs(Math.sin(step * 0.04)) => filt.freq;
            level + 0.01 * Math.sin(step * 0.09) => tone.gain;
            120::ms => now;
            step++;
        }
    }
}

class TelemetryNode
{
    PulseOsc osc;
    LPF filt;
    DelayA echo;
    Pan2 pan;
    Gain out;
    int notes[8];
    float widths[8];
    dur gap;
    float gainValue;

    fun void init(Gain bus, float panValue, float baseGain, dur echoTime, dur baseGap)
    {
        osc => filt => echo => pan => out => bus;
        baseGain => gainValue;
        baseGain => osc.gain;
        1200 => filt.freq;
        2.0 => filt.Q;
        echoTime => echo.max => echo.delay;
        0.22 => echo.gain;
        panValue => pan.pan;
        1.0 => out.gain;
        baseGap => gap;

        [72, 79, 76, 84, 81, 77, 74, 86] @=> notes;
        [0.08, 0.12, 0.18, 0.09, 0.14, 0.11, 0.16, 0.1] @=> widths;
    }

    fun void run(int offset)
    {
        0 => int i;

        while (true)
        {
            Std.mtof(notes[(i + offset) % notes.cap()]) => osc.freq;
            widths[(i + offset) % widths.cap()] => osc.width;
            900 + ((i + offset) % 5) * 170 => filt.freq;
            gainValue + 0.03 * Math.fabs(Math.sin(i * 0.2)) => osc.gain;
            1 => osc.op;
            (40 + ((i + offset) % 3) * 15)::ms => now;
            0 => osc.op;
            gap + ((i + offset) % 4) * 20::ms => now;
            i++;
        }
    }
}

class RelayCluster
{
    Noise src;
    BPF band;
    Envelope env;
    Pan2 pan;
    Gain out;
    float gainValue;

    fun void init(Gain bus, float center, float panValue, float baseGain)
    {
        src => band => env => pan => out => bus;
        center => band.freq;
        8.0 => band.Q;
        baseGain => gainValue;
        baseGain => out.gain;
        panValue => pan.pan;
    }

    fun void tick(dur length)
    {
        1 => env.keyOn;
        length => now;
        1 => env.keyOff;
    }

    fun void run()
    {
        while (true)
        {
            gainValue + Math.random2f(0.0, gainValue) => out.gain;
            tick(8::ms);
            (120 + Math.random2(0, 300))::ms => now;
        }
    }
}

class ScannerSweep
{
    SawOsc osc;
    LPF filt;
    Pan2 pan;
    Gain out;

    fun void init(Gain bus, float panValue)
    {
        osc => filt => pan => out => bus;
        0.04 => osc.gain;
        800 => filt.freq;
        1.0 => filt.Q;
        panValue => pan.pan;
        1.0 => out.gain;
    }

    fun void run()
    {
        while (true)
        {
            for (0 => int i; i < 12; i++)
            {
                Std.mtof(45 + i) => osc.freq;
                700 + i * 120 => filt.freq;
                70::ms => now;
            }

            for (11 => int i; i >= 0; i--)
            {
                Std.mtof(45 + i) => osc.freq;
                700 + i * 120 => filt.freq;
                70::ms => now;
            }
        }
    }
}

class WarningSiren
{
    SqrOsc osc;
    BPF band;
    DelayA echo;
    Pan2 pan;
    Gain out;

    fun void init(Gain bus, float panValue)
    {
        osc => band => echo => pan => out => bus;
        0.07 => osc.gain;
        2100 => band.freq;
        6.0 => band.Q;
        180::ms => echo.max => echo.delay;
        0.18 => echo.gain;
        panValue => pan.pan;
        1.0 => out.gain;
    }

    fun void burst()
    {
        Std.mtof(72) => osc.freq;
        1 => osc.op;
        110::ms => now;
        0 => osc.op;
        80::ms => now;

        Std.mtof(79) => osc.freq;
        1 => osc.op;
        110::ms => now;
        0 => osc.op;
    }

    fun void run()
    {
        while (true)
        {
            burst();
            4::second => now;
            burst();
            6::second => now;
        }
    }
}

class StaticAir
{
    Noise src;
    HPF filt;
    Gain out;

    fun void init(Gain bus)
    {
        src => filt => out => bus;
        3500 => filt.freq;
        0.008 => out.gain;
    }

    fun void run()
    {
        while (true)
        {
            2800 + Math.random2f(0, 2200) => filt.freq;
            0.005 + Math.random2f(0.0, 0.008) => out.gain;
            180::ms => now;
        }
    }
}

class PanelWorld
{
    Gain mix;
    Dyno limiter;
    ControlBed bed1;
    ControlBed bed2;
    TelemetryNode telem1;
    TelemetryNode telem2;
    RelayCluster relays1;
    RelayCluster relays2;
    ScannerSweep scanner;
    WarningSiren siren;
    StaticAir air;

    fun void init()
    {
        mix => limiter => dac;
        0.82 => mix.gain;
        0.9 => limiter.thresh;

        bed1.init(mix, 58.0, 0.055, -0.2);
        bed2.init(mix, 72.0, 0.04, 0.2);
        telem1.init(mix, -0.55, 0.14, 260::ms, 110::ms);
        telem2.init(mix, 0.45, 0.09, 180::ms, 170::ms);
        relays1.init(mix, 2400, -0.1, 0.08);
        relays2.init(mix, 3200, 0.25, 0.06);
        scanner.init(mix, 0.05);
        siren.init(mix, 0.0);
        air.init(mix);
    }

    fun void run()
    {
        spork ~ bed1.run();
        spork ~ bed2.run();
        spork ~ telem1.run(0);
        spork ~ telem2.run(3);
        spork ~ relays1.run();
        spork ~ relays2.run();
        spork ~ scanner.run();
        spork ~ siren.run();
        spork ~ air.run();

        25::second => now;
    }
}

PanelWorld world;
world.init();
world.run();
