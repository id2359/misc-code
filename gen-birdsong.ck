// orac-birdsong.ck
// OOP garden birdsong environment with several bird types

class GardenAir
{
    Noise air;
    LPF tone;
    NRev rev;
    Gain out;

    fun void init(Gain bus)
    {
        air => tone => rev => out => bus;
        2200 => tone.freq;
        0.06 => rev.mix;
        0.01 => out.gain;
    }

    fun void run()
    {
        while (true)
        {
            1600 + Math.random2f(0, 1200) => tone.freq;
            0.006 + Math.random2f(0.0, 0.008) => out.gain;
            300::ms => now;
        }
    }
}

class Bird
{
    fun void run()
    {
        while (true) 1::second => now;
    }
}

class Blackbird extends Bird
{
    Flute voice;
    JCRev rev;
    Pan2 pan;
    Gain out;
    int scale[8];

    fun void init(Gain bus, float panValue)
    {
        voice => rev => pan => out => bus;
        0.08 => rev.mix;
        panValue => pan.pan;
        0.18 => out.gain;
        [72, 74, 76, 79, 81, 83, 84, 86] @=> scale;
    }

    fun void phrase()
    {
        for (0 => int i; i < Math.random2(3, 6); i++)
        {
            Std.mtof(scale[Math.random2(0, scale.cap() - 1)]) => voice.freq;
            Math.random2f(0.3, 0.7) => voice.noteOn;
            (160 + Math.random2(0, 180))::ms => now;
            1 => voice.noteOff;
            (80 + Math.random2(0, 160))::ms => now;
        }
    }

    fun void run()
    {
        while (true)
        {
            phrase();
            (1500 + Math.random2(0, 2500))::ms => now;
        }
    }
}

class Robin extends Bird
{
    BlowBotl voice;
    NRev rev;
    Pan2 pan;
    Gain out;
    int notes[6];

    fun void init(Gain bus, float panValue)
    {
        voice => rev => pan => out => bus;
        0.09 => rev.mix;
        panValue => pan.pan;
        0.12 => out.gain;
        [79, 81, 83, 86, 88, 91] @=> notes;
        voice.controlChange(4, 18);
        voice.controlChange(11, 24);
        voice.controlChange(1, 10);
        voice.controlChange(128, 90);
    }

    fun void chirp()
    {
        Std.mtof(notes[Math.random2(0, notes.cap() - 1)]) => voice.freq;
        Math.random2f(0.35, 0.75) => voice.noteOn;
        (90 + Math.random2(0, 80))::ms => now;
    }

    fun void run()
    {
        while (true)
        {
            for (0 => int i; i < Math.random2(2, 5); i++)
            {
                chirp();
                (60 + Math.random2(0, 90))::ms => now;
            }

            (900 + Math.random2(0, 1500))::ms => now;
        }
    }
}

class Warbler extends Bird
{
    SqrOsc osc;
    LPF filt;
    DelayA echo;
    Pan2 pan;
    Gain out;
    int notes[7];

    fun void init(Gain bus, float panValue)
    {
        osc => filt => echo => pan => out => bus;
        0.05 => osc.gain;
        2400 => filt.freq;
        1.5 => filt.Q;
        140::ms => echo.max => echo.delay;
        0.12 => echo.gain;
        panValue => pan.pan;
        1.0 => out.gain;
        [84, 86, 88, 91, 93, 95, 98] @=> notes;
    }

    fun void trill()
    {
        for (0 => int i; i < Math.random2(4, 9); i++)
        {
            Std.mtof(notes[Math.random2(0, notes.cap() - 1)]) => osc.freq;
            1 => osc.op;
            (35 + Math.random2(0, 30))::ms => now;
            0 => osc.op;
            (20 + Math.random2(0, 40))::ms => now;
        }
    }

    fun void run()
    {
        while (true)
        {
            trill();
            (700 + Math.random2(0, 1400))::ms => now;
        }
    }
}

class Dove extends Bird
{
    SinOsc osc;
    LPF filt;
    NRev rev;
    Pan2 pan;
    Gain out;

    fun void init(Gain bus, float panValue)
    {
        osc => filt => rev => pan => out => bus;
        0.04 => osc.gain;
        900 => filt.freq;
        0.05 => rev.mix;
        panValue => pan.pan;
        1.0 => out.gain;
    }

    fun void coo(float midi)
    {
        Std.mtof(midi) => osc.freq;
        1 => osc.op;
        280::ms => now;
        0 => osc.op;
        90::ms => now;
        Std.mtof(midi - 2) => osc.freq;
        1 => osc.op;
        340::ms => now;
        0 => osc.op;
    }

    fun void run()
    {
        while (true)
        {
            coo(62);
            (1800 + Math.random2(0, 2400))::ms => now;
        }
    }
}

class BirdGarden
{
    Gain mix;
    Dyno limiter;
    GardenAir air;
    Blackbird blackbird;
    Robin robin;
    Warbler warbler;
    Dove dove;

    fun void init()
    {
        mix => limiter => dac;
        0.86 => mix.gain;
        0.92 => limiter.thresh;

        air.init(mix);
        blackbird.init(mix, -0.45);
        robin.init(mix, 0.35);
        warbler.init(mix, 0.0);
        dove.init(mix, -0.1);
    }

    fun void run()
    {
        spork ~ air.run();
        spork ~ blackbird.run();
        spork ~ robin.run();
        spork ~ warbler.run();
        spork ~ dove.run();

        32::second => now;
    }
}

BirdGarden garden;
garden.init();
garden.run();
