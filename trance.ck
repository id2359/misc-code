//------------------------------------------------------//
//   Trance Music Example in ChucK                     //
//   --------------------------------                  //
//   A simple demonstration of a trance-like pattern   //
//   with drums, bass, and pads.                       //
//------------------------------------------------------//

//---------------------------//
// 1) Global Timing Setup    //
//---------------------------//
140 => float BPM;                // beats per minute (try 130-145 for a trance feel)
( 60.0 / BPM ) :: second => dur quarter;       // duration of one quarter note
4 * quarter => dur measure;      // duration of a 4/4 measure

//---------------------------//
// 2) Drum Section           //
//---------------------------//
fun void drumSection() {
    // Kick
    (SinOsc kickOsc) :: Osc  => (LPF kickFilt) :: LPF  => (ADSR kickEnv) :: ADSR => DAC;
    40 => kickOsc.freq;    // deep frequency for the kick
    2000 => kickFilt.freq; // filter the high partials
    0.99 => kickFilt.Q;
    0.01 => kickEnv.attackTime;
    0.05 => kickEnv.decayTime;
    0.0  => kickEnv.sustainLevel;
    0.1  => kickEnv.releaseTime;
    0.5  => kickOsc.gain;  // tweak volume
    
    // Snare
    Noise snareNoise => BPF snareFilt => ADSR snareEnv => DAC;
    2000 => snareFilt.freq;  // band-pass to shape snare noise
    2.5  => snareFilt.Q;
    0.01 => snareEnv.attackTime;
    0.05 => snareEnv.decayTime;
    0.0  => snareEnv.sustainLevel;
    0.2  => snareEnv.releaseTime;
    0.3  => snareNoise.gain; // snare volume
    
    // Hi-Hat
    Noise hatNoise => HPF hatFilt => ADSR hatEnv => DAC;
    8000 => hatFilt.freq;  // high-pass for hats
    0.1  => hatEnv.attackTime;
    0.05 => hatEnv.decayTime;
    0.0  => hatEnv.sustainLevel;
    0.05 => hatEnv.releaseTime;
    0.1  => hatNoise.gain; // hat volume
    
    // Continuously run a 4-beat measure:
    while(true) {
        // Beat index (0,1,2,3) for each quarter note
        for (0 => int i; i < 4; i++) {
            // Kick on every quarter note
            kickEnv.keyOn();
            
            // Snare on beats 2 and 4 (i.e., i == 1 or i == 3)
            if(i == 1 || i == 3) {
                snareEnv.keyOn();
            }
            
            // Open hi-hat on 8th notes (two per quarter for a typical trance loop)
            // We'll quickly spork a little function to fire hats at 8th intervals
            spork ~ playTwoHats();
            
            // Wait one quarter note until next beat
            quarter => now;
        }
    }
}

// Helper function to place two hats per quarter
fun void playTwoHats() {
    // hi-hat defined outside in drumSection
    // but we can recall it as a global reference or just re-declare:
    Noise hatNoise => HPF hatFilt => ADSR hatEnv => blackhole;
    8000 => hatFilt.freq;
    0.1  => hatEnv.attackTime;
    0.05 => hatEnv.decayTime;
    0.0  => hatEnv.sustainLevel;
    0.05 => hatEnv.releaseTime;
    0.1  => hatNoise.gain;
    hatNoise => DAC; // route to DAC
    
    // first 8th
    hatEnv.keyOn();
    quarter/2 => now;
    
    // second 8th
    hatEnv.keyOn();
    quarter/2 => now;
    
    // disconnect so we don't create a new chain forever
    hatNoise =< DAC;
}

//---------------------------//
// 3) Bass Line Section      //
//---------------------------//
// We'll use Moog (STK) for a synth-y bass line.
fun void bassLine() {
    // STK Moog
    Moog moog => ADSR env => JCRev rev => DAC;
    0.5 => rev.mix;               // reverb amount
    0.3 => moog.gain;             // overall volume
    0.001 => env.attackTime;
    0.1   => env.decayTime;
    0.7   => env.sustainLevel;
    0.2   => env.releaseTime;
    
    // A simple trance bass pattern ? feel free to change notes!
    // Let?s define a mini pattern in MIDI notes
    [ 36, 38, 40, 43 ] @=> int bassNotes[];  // C2, D2, E2, G2 (for example)
    
    while(true) {
        // Play each note for one quarter
        for (0 => int i; i < bassNotes.size(); i++) {
            Std.mtof(bassNotes[i]) => moog.freq;
            env.keyOn();
            quarter => now;  // hold note for a quarter beat
        }
    }
}

//---------------------------//
// 4) Pad / Chord Section    //
//---------------------------//
// We'll use STK FM or Rhodey for a pad-like sound.
fun void padChords() {
    // STK Rhodey can be a nice electric piano/pad type
    Rhodey rhodey => ADSR env => JCRev rev => DAC;
    0.7  => rev.mix;                // more reverb
    0.3  => rhodey.gain;            // volume
    0.5  => env.attackTime;         // slow attack for pad
    1.0  => env.decayTime;
    0.7  => env.sustainLevel;
    1.5  => env.releaseTime;
    
    // Let?s pick a 4-chord trance progression in MIDI
    // e.g., C minor chord -> Ab major -> Eb major -> Bb major
    // in root positions (simple). Each chord will last one measure (4 quarters).
    // Chords:
    //   C minor  = C Eb G   = (48, 51, 55)
    //   Ab major = Ab C Eb  = (56, 60, 63)
    //   Eb major = Eb G Bb  = (51, 55, 58)
    //   Bb major = Bb D F   = (58, 62, 65)
    [ [48, 51, 55],
    [56, 60, 63],
    [51, 55, 58],
    [58, 62, 65] ] @=> int chords[][];
    
    while(true) {
        // cycle through each chord
        for (0 => int i; i < chords.size(); i++) {
            // for each chord tone, spork a mini-voice
            for (0 => int n; n < chords[i].size(); n++) {
                spork ~ playPadNote(chords[i][n]);
            }
            // hold chord for one measure
            measure => now;
            // after one measure, fade out (optional)
            env.keyOff();
        }
    }
}

// Helper function to spawn an individual pad note
fun void playPadNote(int midi) {
    // Make a local copy of the chain
    Rhodey r => ADSR e => JCRev j => blackhole;
    0.7  => j.mix;
    0.3  => r.gain;
    0.5  => e.attackTime;
    1.0  => e.decayTime;
    0.7  => e.sustainLevel;
    1.5  => e.releaseTime;
    r => DAC;
    j => DAC; // both direct and reverbed
    
    Std.mtof(midi) => r.freq;
    e.keyOn();
    
    // hold for a measure, then release
    measure => now;
    e.keyOff();
    
    // give it time to fade
    1.5::second => now;
    
    // disconnect from DAC
    r =< DAC;
    j =< DAC;
}

//---------------------------//
// 5) Spork Everything       //
//---------------------------//

spork ~ drumSection();
spork ~ bassLine();
spork ~ padChords();

// Keep the VM alive indefinitely
while(true) { 1::hour => now; }
