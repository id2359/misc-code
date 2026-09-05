// Basic Music Theory, illustrated with sound
// Usage:
// 1. Evaluate this whole block (Cmd/Ctrl+A, Cmd/Ctrl+Enter).
// 2. Run ~demo.() for the full tour (~3 min), or one section:
//    ~playNotes.()  ~playIntervals.()  ~playScales.()  ~playChords.()  ~playProgression.()
// 3. Play single sounds any time: ~tone.(60)  ~chord.([60, 64, 67])
// Stop anytime with Cmd+.  (All MIDI numbers: 60 = C4, 72 = C5.)

(
s.waitForBoot({
	// Soft tone with a touch of harmonics so pitch is clear but never harsh.
	SynthDef(\theoryTone, { |freq = 440, amp = 0.25, sustain = 0.4|
		var env, sig;
		env = EnvGen.kr(Env.perc(0.01, sustain, 1, -4), doneAction: 2);
		sig = SinOsc.ar(freq) * 0.6 + SinOsc.ar(freq * 2) * 0.2 + SinOsc.ar(freq * 3) * 0.1;
		Out.ar(0, Pan2.ar(sig * env * amp, 0));
	}).add;

	s.sync;

	// --- Helpers (no waiting: safe to evaluate directly) ---
	~beat = 0.45;
	~tone = { |midi, sustain = 0.5, amp = 0.25|
		Synth(\theoryTone, [\freq, midi.midicps, \sustain, sustain, \amp, amp]);
	};
	~chord = { |midis, sustain = 1.4, amp = 0.18|
		midis.do({ |m| Synth(\theoryTone, [\freq, m.midicps, \sustain, sustain, \amp, amp]); });
	};
	// Section header; contains a wait, so only call it from inside a Routine.
	~header = { |title| ("--- " ++ title ++ " ---").postln; 0.6.wait; };

	// --- 1. NOTES: chromatic octave C4-C5. 12 semitones = 1 octave. ---
	~seqNotes = {
		var names = ["C", "C#/Db", "D", "D#/Eb", "E", "F", "F#/Gb", "G", "G#/Ab", "A", "A#/Bb", "B", "C"];
		~header.("1. NOTES: C4 to C5 (MIDI 60-72)");
		"Each step up multiplies frequency by 2.pow(1/12) (~6%).".postln;
		13.do({ |i|
			var midi = 60 + i;
			(names[i] ++ ": MIDI " ++ midi ++ " = " ++ midi.midicps.round(0.1) ++ " Hz").postln;
			~tone.(midi, 0.5);
			~beat.wait;
		});
	};

	// --- 2. INTERVALS above C4: hear each melodically, then harmonically. ---
	~seqIntervals = {
		var table = [
			[0, "unison", "same note"],
			[1, "minor 2nd", "Jaws theme, tense"],
			[2, "major 2nd", "Happy Birthday start"],
			[3, "minor 3rd", "sad third"],
			[4, "major 3rd", "happy third"],
			[5, "perfect 4th", "Here Comes the Bride"],
			[6, "tritone", "spooky, unstable"],
			[7, "perfect 5th", "strong, hollow"],
			[8, "minor 6th", "dark"],
			[9, "major 6th", "bright, nostalgic"],
			[10, "minor 7th", "funky, wants to resolve"],
			[11, "major 7th", "dreamy, tense"],
			[12, "octave", "same note, twice as high"]
		];
		~header.("2. INTERVALS above C4");
		table.do({ |row|
			var semis = row[0];
			("C4 + " ++ row[1] ++ " (" ++ semis ++ " semitones): " ++ row[2]).postln;
			~tone.(60, 0.4); ~beat.wait;
			~tone.(60 + semis, 0.5); ~beat.wait;
			~chord.([60, 60 + semis], 1.0); 1.2.wait;
		});
	};

	// --- 3. SCALES: same start note, different recipes of whole (W=2) and half (H=1) steps. ---
	~seqScales = {
		var scales = [
			["major (Ionian): W-W-H-W-W-W-H", [0, 2, 4, 5, 7, 9, 11, 12]],
			["natural minor (Aeolian): W-H-W-W-H-W-W", [0, 2, 3, 5, 7, 8, 10, 12]],
			["major pentatonic (5 notes, always safe)", [0, 2, 4, 7, 9, 12]],
			["blues minor (with the 'blue' flat 5th)", [0, 3, 5, 6, 7, 10, 12]]
		];
		~header.("3. SCALES from C4");
		scales.do({ |entry|
			("Scale: " ++ entry[0]).postln;
			entry[1].do({ |step|
				~tone.(60 + step, 0.45);
				~beat.wait;
			});
			1.0.wait;
		});
	};

	// --- 4. CHORDS: stacked thirds. Melody first, then harmony. ---
	~seqChords = {
		var triads = [
			["C major (happy): root + M3 + P5", [60, 64, 67]],
			["C minor (sad): root + m3 + P5", [60, 63, 67]],
			["C diminished (tense): root + m3 + tritone", [60, 63, 66]],
			["C augmented (dreamy): root + M3 + aug 5th", [60, 64, 68]]
		];
		~header.("4a. TRIADS");
		triads.do({ |entry|
			(entry[0]).postln;
			entry[1].do({ |m| ~tone.(m, 0.4); 0.4.wait; });
			~chord.(entry[1], 1.6); 1.8.wait;
		});
		~header.("4b. SEVENTH CHORDS (triad + a 7th on top)");
		[
			["Cmaj7 (jazzy home)", [60, 64, 67, 71]],
			["C7 dominant (demands resolution)", [60, 64, 67, 70]],
			["Cm7 (mellow)", [60, 63, 67, 70]]
		].do({ |entry|
			(entry[0]).postln;
			~chord.(entry[1], 1.8); 2.0.wait;
		});
		~header.("4c. INVERSIONS of C major (same notes, new bass note)");
		[
			["root position (C on bottom)", [60, 64, 67]],
			["1st inversion (E on bottom)", [64, 67, 72]],
			["2nd inversion (G on bottom)", [67, 72, 76]]
		].do({ |entry|
			(entry[0]).postln;
			~chord.(entry[1], 1.6); 1.8.wait;
		});
	};

	// --- 5. PROGRESSION: I-V-vi-IV in C, pop music's favourite loop. ---
	~seqProgression = {
		var prog = [
			["I  (C major)", [60, 64, 67]],
			["V  (G major)", [55, 59, 62]],
			["vi (A minor)", [57, 60, 64]],
			["IV (F major)", [53, 57, 60]]
		];
		~header.("5. PROGRESSION: I-V-vi-IV in C");
		"Same 4 chords as hundreds of pop songs. Two passes, then home.".postln;
		2.do({
			prog.do({ |entry|
				(entry[0]).postln;
				~chord.(entry[1], 1.6); 1.4.wait;
			});
		});
		"Coda: back home to C.".postln;
		~chord.([48, 60, 64, 67], 2.5); 2.8.wait;
	};

	// --- Runners ---
	~playNotes = { Routine(~seqNotes).play; };
	~playIntervals = { Routine(~seqIntervals).play; };
	~playScales = { Routine(~seqScales).play; };
	~playChords = { Routine(~seqChords).play; };
	~playProgression = { Routine(~seqProgression).play; };
	~demo = {
		Routine({
			~seqNotes.();
			~seqIntervals.();
			~seqScales.();
			~seqChords.();
			~seqProgression.();
			"Done! Replay sections any time, or transpose by replacing 60 with another root.".postln;
		}).play;
	};

	"Basic music theory ready.".postln;
	"Run ~demo.() for the full tour, or one section at a time.".postln;
});
)
