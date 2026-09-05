// Advanced Music Theory, illustrated with sound
// Usage:
// 1. Evaluate this whole block (Cmd/Ctrl+A, Cmd/Ctrl+Enter).
// 2. Run ~ademo.() for the full tour (~5 min), or one section:
//    ~aplayModes.()  ~aplayExt.()  ~aplayVoice.()  ~aplayMod.()  ~aplayChrom.()  ~aplayRhythm.()
// 3. Free play: ~atone.(60)  ~achord.([60, 64, 67])  ~atoneF.(440)
// Stop anytime with Cmd+. . Names with a ~a prefix so this file can coexist with basic_music_theory.scd.

(
s.waitForBoot({
	SynthDef(\advTone, { |freq = 440, amp = 0.22, sustain = 0.5, pan = 0|
		var env, sig;
		env = EnvGen.kr(Env.perc(0.01, sustain, 1, -4), doneAction: 2);
		sig = SinOsc.ar(freq) * 0.6 + SinOsc.ar(freq * 2) * 0.2 + SinOsc.ar(freq * 3) * 0.1;
		Out.ar(0, Pan2.ar(sig * env * amp, pan));
	}).add;

	SynthDef(\advClick, { |freq = 1000, amp = 0.3, pan = 0|
		var env;
		env = EnvGen.kr(Env.perc(0.005, 0.12, 1, -4), doneAction: 2);
		Out.ar(0, Pan2.ar(SinOsc.ar(freq) * env * amp, pan));
	}).add;

	s.sync;

	// Helpers (no waiting: safe to evaluate directly).
	~abeat = 0.42;
	~atone = { |midi, sustain = 0.5, amp = 0.22, pan = 0|
		Synth(\advTone, [\freq, midi.midicps, \sustain, sustain, \amp, amp, \pan, pan]);
	};
	~atoneF = { |freq, sustain = 1.6, amp = 0.2|
		Synth(\advTone, [\freq, freq, \sustain, sustain, \amp, amp]);
	};
	~achord = { |midis, sustain = 1.6, amp = 0.16|
		midis.do({ |m| Synth(\advTone, [\freq, m.midicps, \sustain, sustain, \amp, amp]); });
	};
	~aclick = { |freq = 1000, pan = 0|
		Synth(\advClick, [\freq, freq, \pan, pan]);
	};
	// Header contains a wait: only call from inside a Routine.
	~ahead = { |title| ("--- " ++ title ++ " ---").postln; 0.6.wait; };

	// --- 1. MODES, parallel on C: same root, shifting color, brightest first. ---
	~aseqModes = {
		var modes = [
			["Lydian (#4, floating)", [0, 2, 4, 6, 7, 9, 11, 12]],
			["Ionian = major (happy default)", [0, 2, 4, 5, 7, 9, 11, 12]],
			["Mixolydian (bluesy major, flat 7)", [0, 2, 4, 5, 7, 9, 10, 12]],
			["Dorian (minor with a hopeful 6th)", [0, 2, 3, 5, 7, 9, 10, 12]],
			["Aeolian = natural minor (sad default)", [0, 2, 3, 5, 7, 8, 10, 12]],
			["Phrygian (dark, flat 2)", [0, 1, 3, 5, 7, 8, 10, 12]],
			["Locrian (unstable, flat 2 + flat 5)", [0, 1, 3, 5, 6, 8, 10, 12]]
		];
		~ahead.("1. MODES, all starting on C (brightest first)");
		"Only one note changes at each step. Listen for the color draining away.".postln;
		modes.do({ |entry|
			("Mode: C " ++ entry[0]).postln;
			entry[1].do({ |step| ~atone.(60 + step, 0.45); ~abeat.wait; });
			1.0.wait;
		});
	};

	// --- 2. EXTENDED CHORDS: 7ths grow 9ths and 13ths, then an altered dominant. ---
	~aseqExt = {
		~ahead.("2. EXTENDED CHORDS (arpeggio, then block)");
		[
			["Cmaj9 (C E G B D): warm jazz home", [60, 64, 67, 71, 74]],
			["Cm9 (C Eb G Bb D): rainy window", [60, 63, 67, 70, 74]],
			["C13 (C E Bb D A, no 5th): funky dominant", [60, 64, 70, 74, 81]],
			["C7alt (C E Bb Db F#: tense, must resolve)", [60, 64, 70, 73, 78]]
		].do({ |entry|
			(entry[0]).postln;
			entry[1].do({ |m| ~atone.(m, 0.4); 0.35.wait; });
			0.3.wait;
			~achord.(entry[1], 2.0); 2.2.wait;
		});
		"Resolution: C7alt -> F.".postln;
		~achord.([60, 64, 70, 73, 78], 1.2); 1.3.wait;
		~achord.([53, 57, 60, 65], 2.2); 2.4.wait;
	};

	// --- 3. VOICE LEADING: ii-V-I, choppy root positions vs smooth jazz voicing. ---
	~aseqVoice = {
		~ahead.("3. VOICE LEADING: Dm7 - G7 - Cmaj7");
		"Choppy first: root positions, everything leaps.".postln;
		~achord.([62, 65, 69, 72], 1.4); 1.5.wait;
		~achord.([55, 59, 62, 65], 1.4); 1.5.wait;
		~achord.([48, 52, 55, 59], 2.0); 2.2.wait;
		"Smooth version: most voices move by step or stay put.".postln;
		"Dm7 [D F A C] -> G7 [D F G B]: only A falls to G, C falls to B.".postln;
		~achord.([62, 65, 69, 72], 1.6); 1.7.wait;
		~achord.([62, 65, 67, 71], 1.6); 1.7.wait;
		"G7 -> Cmaj7 [C E G B]: D falls to C, F falls to E, G and B stay.".postln;
		~achord.([60, 64, 67, 71], 2.4); 2.6.wait;
	};

	// --- 4. MODULATION: changing home key mid-song. ---
	~aseqMod = {
		~ahead.("4a. RELATIVE MAJOR/MINOR: C major vs A minor (same 7 notes, new home)");
		"C major: I - V - vi - IV.".postln;
		~achord.([60, 64, 67], 1.2); 1.3.wait;
		~achord.([55, 59, 62], 1.2); 1.3.wait;
		~achord.([57, 60, 64], 1.2); 1.3.wait;
		~achord.([53, 57, 60], 1.2); 1.3.wait;
		"A minor: i - VI - III - VII.".postln;
		~achord.([57, 60, 64], 1.2); 1.3.wait;
		~achord.([53, 57, 60], 1.2); 1.3.wait;
		~achord.([48, 52, 55], 1.2); 1.3.wait;
		~achord.([55, 59, 62], 1.2); 1.3.wait;
		~achord.([57, 60, 64], 2.0); 2.2.wait;
		~ahead.("4b. PIVOT CHORD: Am is vi in C, then ii in G");
		"In C: C - F - Am.".postln;
		~achord.([60, 64, 67], 1.2); 1.3.wait;
		~achord.([53, 57, 60], 1.2); 1.3.wait;
		~achord.([57, 60, 64], 1.4); 1.5.wait;
		"Same Am, new meaning: ii - D7 - G. We are in G major now.".postln;
		~achord.([57, 60, 64], 1.2); 1.3.wait;
		~achord.([50, 54, 57, 60], 1.2); 1.3.wait;
		~achord.([55, 59, 62], 2.0); 2.2.wait;
		~ahead.("4c. TRUCK-DRIVER MODULATION: I - V - I in C, then up a semitone");
		~achord.([60, 64, 67], 1.0); 1.1.wait;
		~achord.([55, 59, 62], 1.0); 1.1.wait;
		~achord.([60, 64, 67], 1.4); 1.5.wait;
		"Key change! Same shapes in Db.".postln;
		~achord.([61, 65, 68], 1.0); 1.1.wait;
		~achord.([56, 60, 63], 1.0); 1.1.wait;
		~achord.([61, 65, 68], 2.0); 2.2.wait;
	};

	// --- 5. CHROMATIC HARMONY: tension borrowed from outside the key. ---
	~aseqChrom = {
		~ahead.("5a. SECONDARY DOMINANT: D7 is the V of G, borrowed into C major");
		"Plain: C - G - C.".postln;
		~achord.([60, 64, 67], 1.2); 1.3.wait;
		~achord.([55, 59, 62], 1.2); 1.3.wait;
		~achord.([60, 64, 67], 1.6); 1.7.wait;
		"Spicier: C - D7 - G - C. The F# is foreign to C major and pulls toward G.".postln;
		~achord.([60, 64, 67], 1.2); 1.3.wait;
		~achord.([50, 54, 57, 60], 1.2); 1.3.wait;
		~achord.([55, 59, 62], 1.2); 1.3.wait;
		~achord.([60, 64, 67], 2.0); 2.2.wait;
		~ahead.("5b. TRITONE SUBSTITUTION: Db7 instead of G7, same tritone resolves to C");
		"G7 (G B D F) and Db7 (Db F Ab B) share the tritone B-F.".postln;
		~achord.([55, 59, 62, 65], 1.4); 1.5.wait;
		~achord.([60, 64, 67], 1.6); 1.7.wait;
		"Now with the sub: C - Db7 - C. Hear the chromatic bass slide.".postln;
		~achord.([60, 64, 67], 1.2); 1.3.wait;
		~achord.([49, 53, 56, 59], 1.4); 1.5.wait;
		~achord.([60, 64, 67], 2.2); 2.4.wait;
	};

	// --- 6a. POLYRHYTHM 3 against 2: low-left plays 3, high-right plays 2. ---
	~aseqRhythm = {
		~ahead.("6a. POLYRHYTHM 3:2");
		"One bar is 2.4 seconds. Low-left hits 3 times, high-right twice.".postln;
		2.do({
			~aclick.(660, -0.8); ~aclick.(990, 0.8); 0.8.wait;
			~aclick.(660, -0.8); 0.4.wait;
			~aclick.(990, 0.8); 0.4.wait;
			~aclick.(660, -0.8); 0.8.wait;
		});
		"The 3:2 groove behind Afro-Cuban music, in your headphones.".postln;
		1.0.wait;
	};

	// --- 6b. TUNING: piano tuning vs pure just intonation. ---
	~aseqTune = {
		var c = 261.63;
		~ahead.("6b. TUNING: equal temperament vs just intonation");
		"Equal temperament C major (piano tuning).".postln;
		("ET third: " ++ (c * 2.pow(4 / 12)).round(0.1) ++ " Hz").postln;
		~atoneF.(c, 2.0); ~atoneF.(c * 2.pow(4 / 12), 2.0); ~atoneF.(c * 2.pow(7 / 12), 2.0);
		2.4.wait;
		"Just intonation: pure 5/4 third and 3/2 fifth, no beating.".postln;
		("Just third: " ++ (c * 1.25).round(0.1) ++ " Hz, ~14 cents flatter.").postln;
		~atoneF.(c, 2.0); ~atoneF.(c * 1.25, 2.0); ~atoneF.(c * 1.5, 2.0);
		2.4.wait;
		"Back to back: ET, then just.".postln;
		~atoneF.(c, 1.2); ~atoneF.(c * 2.pow(4 / 12), 1.2); ~atoneF.(c * 2.pow(7 / 12), 1.2);
		1.6.wait;
		~atoneF.(c, 1.2); ~atoneF.(c * 1.25, 1.2); ~atoneF.(c * 1.5, 1.2);
		1.6.wait;
	};

	// --- Runners ---
	~aplayModes = { Routine(~aseqModes).play; };
	~aplayExt = { Routine(~aseqExt).play; };
	~aplayVoice = { Routine(~aseqVoice).play; };
	~aplayMod = { Routine(~aseqMod).play; };
	~aplayChrom = { Routine(~aseqChrom).play; };
	~aplayRhythm = { Routine({ ~aseqRhythm.(); ~aseqTune.(); }).play; };
	~ademo = {
		Routine({
			~aseqModes.();
			~aseqExt.();
			~aseqVoice.();
			~aseqMod.();
			~aseqChrom.();
			~aseqRhythm.();
			~aseqTune.();
			"Done! Steal the smooth ii-V-I and the tritone sub for your own progressions.".postln;
		}).play;
	};

	"Advanced theory ready.".postln;
	"Run ~ademo.() for the full tour, or one section at a time.".postln;
});
)
