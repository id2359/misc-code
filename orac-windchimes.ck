// orac-windchimes.ck
// OOP windchime environment with multiple materials

class WindDriver
{
    float gust;

    fun void run()
    {
        while (true)
        {
            0.2 + Math.random2f(0.0, 0.8) => gust;
            (400 + Math.random2(0, 1000))::ms => now;
        }
    }
}

class ChimeVoice
{
    StifKarp body;
    NRev rev;
    Pan2 pan;
    Gain out;
    int notes[8];
    float gainValue;
    float sustainBase;
    float stretchBase;
    float panValue;

    fun void init(Gain bus, int noteSet[], float baseGain, float sustainValue, float stretchValue, float pos)
    {
        body => rev => pan => out => bus;
        noteSet @=> notes;
        baseGain => gainValue;
        sustainValue => sustainBase;
        stretchValue => stretchBase;
        pos => panValue;
        0.08 => rev.mix;
        pos => pan.pan;
        1.0 => out.gain;
    }

    fun void strike(float force)
    {
        notes[Math.random2(0, notes.cap() - 1)] => int note;
        Std.mtof(note + Math.random2(-12, 12)) => body.freq;
        Math.random2f(0.2, 0.8) => body.pickupPosition;
        Math.min(1.0, sustainBase + Math.random2f(-0.1, 0.2)) => body.sustain;
        Math.min(1.0, stretchBase + Math.random2f(-0.15, 0.15)) => body.stretch;
        gainValue * force => out.gain;
        Math.min(1.0, 0.25 + force * 0.6) => body.pluck;
    }

    fun void run(WindDriver wind, float density)
    {
        while (true)
        {
            if (Math.random2f(0.0, 1.0) < wind.gust * density)
            {
                strike(wind.gust);
            }

            (140 + Math.random2(0, 600))::ms => now;
        }
    }
}

class TubeChime extends ChimeVoice
{
    fun void strike(float force)
    {
        notes[Math.random2(0, notes.cap() - 1)] => int note;
        Std.mtof(note) => body.freq;
        0.35 => body.pickupPosition;
        Math.min(1.0, sustainBase + 0.15 * force) => body.sustain;
        Math.min(1.0, stretchBase + 0.05) => body.stretch;
        gainValue * (0.8 + force * 0.4) => out.gain;
        Math.min(1.0, 0.35 + force * 0.5) => body.pluck;
    }
}

class GlassChime extends ChimeVoice
{
    fun void strike(float force)
    {
        notes[Math.random2(0, notes.cap() - 1)] => int note;
        Std.mtof(note + 12) => body.freq;
        0.75 => body.pickupPosition;
        Math.min(1.0, sustainBase + 0.05 * force) => body.sustain;
        Math.min(1.0, stretchBase + 0.2) => body.stretch;
        gainValue * (0.7 + force * 0.3) => out.gain;
        Math.min(1.0, 0.2 + force * 0.35) => body.pluck;
    }
}

class BambooChime extends ChimeVoice
{
    fun void strike(float force)
    {
        notes[Math.random2(0, notes.cap() - 1)] => int note;
        Std.mtof(note - 12) => body.freq;
        0.18 => body.pickupPosition;
        Math.min(1.0, sustainBase + 0.08 * force) => body.sustain;
        Math.max(0.0, stretchBase - 0.12) => body.stretch;
        gainValue * (0.6 + force * 0.25) => out.gain;
        Math.min(1.0, 0.18 + force * 0.25) => body.pluck;
    }
}

class AirBed
{
    Noise air;
    HPF airHPF;
    LPF airLPF;
    Gain out;

    fun void init(Gain bus)
    {
        air => airHPF => airLPF => out => bus;
        1800 => airHPF.freq;
        5200 => airLPF.freq;
        0.012 => out.gain;
    }

    fun void run(WindDriver wind)
    {
        while (true)
        {
            1400 + wind.gust * 1800 => airHPF.freq;
            4200 + wind.gust * 1800 => airLPF.freq;
            0.006 + wind.gust * 0.016 => out.gain;
            120::ms => now;
        }
    }
}

class ChimeGarden
{
    Gain mix;
    Dyno limiter;
    WindDriver wind;
    AirBed air;
    TubeChime metal;
    GlassChime glass;
    BambooChime bamboo;

    fun void init()
    {
        mix => limiter => dac;
        0.82 => mix.gain;
        0.92 => limiter.thresh;

        air.init(mix);

        [72, 79, 84, 86, 91, 96, 98, 103] @=> int metalNotes[];
        [79, 84, 86, 91, 96, 98, 103, 108] @=> int glassNotes[];
        [55, 60, 62, 67, 69, 72, 74, 79] @=> int bambooNotes[];

        metal.init(mix, metalNotes, 0.18, 0.82, 0.7, -0.45);
        glass.init(mix, glassNotes, 0.13, 0.58, 0.88, 0.35);
        bamboo.init(mix, bambooNotes, 0.16, 0.66, 0.3, 0.0);
    }

    fun void run()
    {
        spork ~ wind.run();
        spork ~ air.run(wind);
        spork ~ metal.run(wind, 0.36);
        spork ~ glass.run(wind, 0.24);
        spork ~ bamboo.run(wind, 0.42);

        30::second => now;
    }
}

ChimeGarden garden;
garden.init();
garden.run();
