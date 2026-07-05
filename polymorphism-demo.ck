// polymorphism-demo.ck
// Small ChuCk example showing inheritance and overridden behavior

class Bird
{
    Gain @ bus;
    Pan2 pan;
    Gain out;
    float panValue;

    fun void init(Gain target, float pos)
    {
        target @=> bus;
        pos => panValue;
    }

    fun void connect(UGen source)
    {
        source => pan => out => bus;
        panValue => pan.pan;
        1.0 => out.gain;
    }

    fun void sing()
    {
        <<< "generic bird" >>>;
        200::ms => now;
    }
}

class Robin extends Bird
{
    SinOsc osc;

    fun void init(Gain target, float pos)
    {
        target @=> bus;
        pos => panValue;
        connect(osc);
        0.05 => osc.gain;
    }

    fun void sing()
    {
        <<< "robin chirp" >>>;
        Std.mtof(84) => osc.freq;
        1 => osc.op;
        120::ms => now;
        0 => osc.op;
        80::ms => now;
    }
}

class Dove extends Bird
{
    TriOsc osc;

    fun void init(Gain target, float pos)
    {
        target @=> bus;
        pos => panValue;
        connect(osc);
        0.04 => osc.gain;
    }

    fun void sing()
    {
        <<< "dove coo" >>>;
        Std.mtof(62) => osc.freq;
        1 => osc.op;
        260::ms => now;
        0 => osc.op;
        100::ms => now;
    }
}

Gain mix => dac;
0.7 => mix.gain;

Robin robin;
Dove dove;

robin.init(mix, -0.3);
dove.init(mix, 0.3);

Bird flock[2];
robin @=> flock[0];
dove @=> flock[1];

for (0 => int i; i < 6; i++)
{
    flock[i % flock.cap()].sing();
}
