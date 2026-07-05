// orac1.ck
// Moog-flavoured waltz arrangement of "Waltzing Matilda"

120.0 => float bpm;
(60.0 / bpm) :: second => dur Q;
2 * Q => dur H;
3 * Q => dur DH;

Moog lead => NRev leadRev => Pan2 leadPan => dac;
Moog bass => LPF bassTone => NRev bassRev => Pan2 bassPan => dac;
Moog pads[3];
NRev padRev => Pan2 padPan => dac;

for (0 => int i; i < pads.cap(); i++)
{
    pads[i] => padRev;
    0.18 => pads[i].filterQ;
    0.22 => pads[i].filterSweepRate;
    0.15 => pads[i].vibratoGain;
    5.0 => pads[i].modSpeed;
}

0.07 => leadRev.mix;
0.04 => bassRev.mix;
0.09 => padRev.mix;

-0.15 => leadPan.pan;
0.0 => padPan.pan;
0.1 => bassPan.pan;

900 => bassTone.freq;
1.4 => bassTone.Q;

0.22 => lead.filterQ;
0.35 => lead.filterSweepRate;
0.20 => lead.vibratoGain;
5.5 => lead.modSpeed;

0.30 => bass.filterQ;
0.18 => bass.filterSweepRate;
0.08 => bass.vibratoGain;
4.0 => bass.modSpeed;

[62, 67, 71, 74, 71, 67,
 69, 71, 69, 67, 64, 67,
 69, 71, 69, 67, 64, 64,
 62, 67, 71, 74, 71, 67,
 69, 71, 69, 67, 64, 67,
 69, 67, 64, 62, 60, 67] @=> int melodyNotes[];

[Q, Q, Q, Q, Q, Q,
 Q, Q, Q, H, Q, Q,
 Q, Q, Q, H, Q, Q,
 Q, Q, Q, Q, Q, Q,
 Q, Q, Q, H, Q, Q,
 Q, Q, Q, Q, Q, DH] @=> dur melodyDurs[];

[43, 43, 50, 50, 43, 43, 38, 38,
 43, 43, 50, 50, 43, 38, 43, 43] @=> int bassRoots[];

fun void playLeadNote(int midi, dur length, float velocity)
{
    Std.mtof(midi) => lead.freq;
    velocity => lead.noteOn;
    length * 0.88 => now;
    0.0 => lead.noteOff;
    length * 0.12 => now;
}

fun void playBassNote(int midi, dur length, float velocity)
{
    Std.mtof(midi) => bass.freq;
    velocity => bass.noteOn;
    length * 0.82 => now;
    0.0 => bass.noteOff;
    length * 0.18 => now;
}

fun void playChord(int notes[], dur length, float velocity)
{
    for (0 => int i; i < notes.cap() && i < pads.cap(); i++)
    {
        Std.mtof(notes[i]) => pads[i].freq;
        velocity => pads[i].noteOn;
    }

    length * 0.78 => now;

    for (0 => int i; i < notes.cap() && i < pads.cap(); i++)
    {
        0.0 => pads[i].noteOff;
    }

    length * 0.22 => now;
}

fun void waltzBar(int root, int chordNotes[])
{
    playBassNote(root, Q, 0.72);
    playChord(chordNotes, Q, 0.34);
    playChord(chordNotes, Q, 0.28);
}

fun void accompaniment()
{
    [67, 71, 74] @=> int gMaj[];
    [69, 72, 76] @=> int aMin[];
    [71, 74, 78] @=> int bMin[];
    [62, 66, 69] @=> int dMaj[];
    [60, 64, 67] @=> int cMaj[];

    for (0 => int bar; bar < bassRoots.cap(); bar++)
    {
        if (bar == 0 || bar == 1 || bar == 4 || bar == 5 || bar == 8 || bar == 9 || bar == 15)
        {
            waltzBar(bassRoots[bar], gMaj);
        }
        else if (bar == 2 || bar == 10)
        {
            waltzBar(bassRoots[bar], dMaj);
        }
        else if (bar == 3 || bar == 11)
        {
            waltzBar(bassRoots[bar], gMaj);
        }
        else if (bar == 6 || bar == 13)
        {
            waltzBar(bassRoots[bar], aMin);
        }
        else if (bar == 7 || bar == 14)
        {
            waltzBar(bassRoots[bar], dMaj);
        }
        else if (bar == 12)
        {
            waltzBar(bassRoots[bar], cMaj);
        }
        else
        {
            waltzBar(bassRoots[bar], bMin);
        }
    }
}

spork ~ accompaniment();

for (0 => int i; i < melodyNotes.cap(); i++)
{
    0.55 + 0.12 * Math.sin(i * 0.35) => float vel;
    playLeadNote(melodyNotes[i], melodyDurs[i], vel);
}

2::second => now;
