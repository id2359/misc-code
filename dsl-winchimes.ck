// dsl-winchimes.ck
// Text-driven windchime composition with a built-in fallback sequence
//
// DSL format: one event = 4 whitespace-separated tokens
// material midi-note force gap-ms
//
// Example:
// metal 84 0.8 220
// glass 91 0.5 380
// bamboo 67 0.7 260

class ChimeVoice
{
    StifKarp body;
    NRev rev;
    Pan2 pan;
    Gain out;
    float gainValue;
    float sustainBase;
    float stretchBase;

    fun void init(Gain bus, float baseGain, float sustainValue, float stretchValue, float panValue)
    {
        body => rev => pan => out => bus;
        baseGain => gainValue;
        sustainValue => sustainBase;
        stretchValue => stretchBase;
        0.08 => rev.mix;
        panValue => pan.pan;
        1.0 => out.gain;
    }

    fun void strike(int midiNote, float force)
    {
        Std.mtof(midiNote) => body.freq;
        Math.random2f(0.2, 0.8) => body.pickupPosition;
        Math.min(1.0, sustainBase + Math.random2f(-0.1, 0.2)) => body.sustain;
        Math.min(1.0, stretchBase + Math.random2f(-0.15, 0.15)) => body.stretch;
        gainValue * force => out.gain;
        Math.min(1.0, 0.25 + force * 0.6) => body.pluck;
    }
}

class TubeChime extends ChimeVoice
{
    fun void strike(int midiNote, float force)
    {
        Std.mtof(midiNote) => body.freq;
        0.35 => body.pickupPosition;
        Math.min(1.0, sustainBase + 0.15 * force) => body.sustain;
        Math.min(1.0, stretchBase + 0.05) => body.stretch;
        gainValue * (0.8 + force * 0.4) => out.gain;
        Math.min(1.0, 0.35 + force * 0.5) => body.pluck;
    }
}

class GlassChime extends ChimeVoice
{
    fun void strike(int midiNote, float force)
    {
        Std.mtof(midiNote + 12) => body.freq;
        0.75 => body.pickupPosition;
        Math.min(1.0, sustainBase + 0.05 * force) => body.sustain;
        Math.min(1.0, stretchBase + 0.2) => body.stretch;
        gainValue * (0.7 + force * 0.3) => out.gain;
        Math.min(1.0, 0.2 + force * 0.35) => body.pluck;
    }
}

class BambooChime extends ChimeVoice
{
    fun void strike(int midiNote, float force)
    {
        Std.mtof(midiNote - 12) => body.freq;
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

    fun void run()
    {
        while (true)
        {
            1600 + Math.random2f(0, 1800) => airHPF.freq;
            4200 + Math.random2f(0, 1600) => airLPF.freq;
            0.006 + Math.random2f(0.0, 0.012) => out.gain;
            140::ms => now;
        }
    }
}

class SequenceConfig
{
    128 => static int MAX_EVENTS;
    int materials[MAX_EVENTS];
    int notes[MAX_EVENTS];
    float forces[MAX_EVENTS];
    int gapsMs[MAX_EVENTS];
    int count;

    fun void clear()
    {
        0 => count;
    }

    fun void add(int material, int note, float force, int gapMs)
    {
        if (count < MAX_EVENTS)
        {
            material => materials[count];
            note => notes[count];
            force => forces[count];
            gapMs => gapsMs[count];
            count++;
        }
    }

    fun int materialId(string material)
    {
        if (material == "metal") return 0;
        if (material == "glass") return 1;
        if (material == "bamboo") return 2;
        return -1;
    }

    fun void loadDefault()
    {
        clear();
        add(0, 84, 0.85, 220);
        add(1, 91, 0.55, 380);
        add(2, 67, 0.70, 240);
        add(0, 79, 0.65, 260);
        add(1, 96, 0.45, 420);
        add(2, 72, 0.60, 200);
        add(0, 86, 0.80, 180);
        add(1, 103, 0.50, 500);
        add(2, 74, 0.75, 260);
        add(0, 91, 0.70, 240);
        add(1, 98, 0.52, 360);
        add(2, 79, 0.68, 300);
    }

    fun int loadFromFile(string filename)
    {
        FileIO fio;
        fio.open(filename, FileIO.READ);

        if (!fio.good())
        {
            return 0;
        }

        clear();

        string material;
        int note;
        float force;
        int gapMs;
        int mid;

        while (fio.more())
        {
            fio => material;
            if (!fio.more()) break;
            fio => note;
            if (!fio.more()) break;
            fio => force;
            if (!fio.more()) break;
            fio => gapMs;

            materialId(material) => mid;
            if (mid >= 0)
            {
                add(mid, note, force, gapMs);
            }
        }

        return count > 0;
    }
}

class ChimeDSLWorld
{
    Gain mix;
    Dyno limiter;
    AirBed air;
    TubeChime metal;
    GlassChime glass;
    BambooChime bamboo;
    SequenceConfig seq;

    fun void init()
    {
        mix => limiter => dac;
        0.82 => mix.gain;
        0.92 => limiter.thresh;

        air.init(mix);
        metal.init(mix, 0.18, 0.82, 0.7, -0.45);
        glass.init(mix, 0.13, 0.58, 0.88, 0.35);
        bamboo.init(mix, 0.16, 0.66, 0.3, 0.0);
    }

    fun void playEvent(int material, int note, float force)
    {
        if (material == 0) metal.strike(note, force);
        else if (material == 1) glass.strike(note, force);
        else if (material == 2) bamboo.strike(note, force);
    }

    fun void playSequence()
    {
        for (0 => int i; i < seq.count; i++)
        {
            playEvent(seq.materials[i], seq.notes[i], seq.forces[i]);
            seq.gapsMs[i]::ms => now;
        }
    }

    fun void run(string filename)
    {
        if (filename != "" && seq.loadFromFile(filename))
        {
            <<< "loaded chime sequence from", filename >>>;
        }
        else
        {
            <<< "using built-in chime sequence", "" >>>;
            seq.loadDefault();
        }

        spork ~ air.run();

        while (true)
        {
            playSequence();
            900::ms => now;
        }
    }
}

"" => string filename;
if (me.args() > 0) me.arg(0) => filename;

ChimeDSLWorld world;
world.init();
world.run(filename);
