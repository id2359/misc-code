// Advanced SuperCollider: Routines, Clocks, Tasks, Patterns, Streams
// How to use: evaluate section 0 first (boots the server, builds the instruments).
// Then evaluate sections 1-8 one at a time, in order. Each prints what it is doing.
// Panic button (evaluates anytime): ~stopAll.()
// Full auto-tour: ~tour.()  (plays every demo back to back, ~2 min)

// ============ 0. SETUP: instruments every demo below uses ============
(
s.waitForBoot({
	// Bright pluck: default voice for the Pbind demos.
	SynthDef(\patPluck, { |freq = 440, amp = 0.2, sustain = 0.4, pan = 0|
		var env, sig;
		env = EnvGen.kr(Env.perc(0.005, sustain, 1, -4), doneAction: 2);
		sig = Saw.ar(freq) * 0.4 + SinOsc.ar(freq * 2) * 0.2;
		sig = LPF.ar(sig, (800 + (freq * 4)).clip(800, 6000));
		Out.ar(0, Pan2.ar(sig * env * amp, pan));
	}).add;

	// Deep round bass.
	SynthDef(\patBass, { |freq = 110, amp = 0.3, sustain = 0.35|
		var env, sig;
		env = EnvGen.kr(Env.perc(0.01, sustain, 1, -4), doneAction: 2);
		sig = SinOsc.ar(freq) * 0.7 + SinOsc.ar(freq * 0.5) * 0.5;
		Out.ar(0, Pan2.ar(sig * env * amp, 0));
	}).add;

	// Tiny noise hat for rhythm patterns.
	SynthDef(\patHat, { |amp = 0.12, sustain = 0.05, pan = 0|
		var env, sig;
		env = EnvGen.kr(Env.perc(0.001, sustain, 1, -8), doneAction: 2);
		sig = HPF.ar(WhiteNoise.ar(1), 7000);
		Out.ar(0, Pan2.ar(sig * env * amp, pan));
	}).add;

	// Demand UGens: pattern-style sequencing INSIDE one synth (sample-accurate).
	SynthDef(\dseqDemo, {
		var trig = Impulse.kr(8);
		var seq = Demand.kr(trig, 0, Dseq([220, 277.18, 329.63, 440], inf));
		var env = Decay2.kr(trig, 0.01, 0.2);
		Out.ar(0, Pan2.ar(SinOsc.ar(seq) * env * 0.25, 0));
	}).add;

	s.sync;

	// Panic button: stops players, clears live-coding proxies, resets tempo.
	~stopAll = {
		CmdPeriod.run;
		Pdef.clear;
		Tdef.clear;
		TempoClock.default.tempo = 1;
		"Everything stopped.".postln;
	};

	"Setup ready. Work through sections 1-8, or run ~tour.().".postln;
});
)

// ============ 1. ROUTINES: functions that can pause themselves ============
// A Routine runs until .wait, then freezes; the clock wakes it up later.
(
~r = Routine({
	loop({
		"C".postln; 1.wait;  // waits are in BEATS on the clock it plays on
		"D".postln; 1.wait;
	});
});
~r.play;
)
// Evaluate these one at a time to feel the lifecycle:
// ~r.pause;   // freeze mid-loop     ~r.resume;  // carry on
// ~r.stop;    // kill it             ~r.reset; ~r.play;  // start over from the top

// A Routine is also a Stream: pull values out of it by hand with .next.
(
var melody = Routine({
	[60, 62, 64, 67].do({ |m| m.yield; });  // yield hands a value OUT to whoever called .next
	"end".yield;
});
8.do({ melody.next.postln; });  // 60 62 64 67 end nil nil nil
)

// ============ 2. CLOCKS: who counts the beats ============
// TempoClock.default drives every .play below. Change it and live players follow.
(
TempoClock.default.tempo = 2;  // 2 beats per second
~p1 = Pbind(
	\instrument, \patPluck,
	\midinote, Pseq([60, 64, 67, 72], inf),
	\dur, 0.25
).play;
)
// While it plays, evaluate: TempoClock.default.tempo = 4;  (then 1, then 0.5)
// ~p1.stop;  TempoClock.default.tempo = 1;  // tidy up

// Play a Routine on YOUR OWN clock and only it is affected:
(
~myClock = TempoClock(3);
~tick = Routine({ loop({ "tick".postln; 1.wait; }) }).play(~myClock);
)
// ~tick.stop;

// ============ 3. PBIND: one pattern per musical dimension ============
// Every key (\midinote, \dur, \amp...) gets its OWN pattern; the event system
// merges one value from each per note. Different lengths interlock (polyrhythm of values).
(
~p2 = Pbind(
	\instrument, \patPluck,
	\midinote, Pseq([60, 64, 67, 72, 76, 72, 67, 64], 1),  // 8 notes, then the player ends itself
	\dur, 0.25,
	\amp, Pseq([0.3, 0.1, 0.2, 0.1], inf),                 // 4-step accent loop over the 8 notes
	\legato, 0.8,
	\pan, Pwhite(-0.8, 0.8, inf)                           // new random pan per note
).play;
)
// ~p2.stop;  (~p2 is also an EventStreamPlayer: try ~p2.pause / ~p2.resume / ~p2.reset)

// ============ 4. VALUE PATTERNS: the vocabulary ============
(
~p3 = Pbind(
	\instrument, \patPluck,
	\midinote, Prand([60, 64, 67, 72, 76], inf),              // random, repeats allowed
	\dur, Pwrand([0.25, 0.5, 0.125], [0.5, 0.3, 0.2], inf),   // weighted random
	\amp, Pbrown(0.05, 0.35, 0.05, inf)                       // drunk walk: each amp near the last
).play;
)
// ~p3.stop;
// Cheat sheet (each takes a repeats arg; inf = forever):
// Pseq(list, n)   in order            Prand(list, n)   random with repeats
// Pxrand(list, n) random, no immediate repeats          Pshuf(list, n)  shuffled
// Pseries(lo, step, n)  arithmetic    Pgeom(lo, grow, n)  geometric
// Pwhite(lo, hi, n)  uniform          Pbrown(lo, hi, step, n)  random walk
// Pfunc({ ... })  run code per event: Pfunc({ rrand(0.05, 0.3) })
// Pkey(\dur)      reuse another key's value, e.g. \sustain, Pkey(\dur) * 2

// ============ 5. DEGREES + SCALES: think in key, not MIDI ============
(
~p4 = Pbind(
	\instrument, \patBass,
	\degree, Pseq([0, 3, 4, 3], inf),  // scale steps, not semitones
	\scale, Scale.minor,
	\root, 0,                          // C
	\octave, 3,
	\dur, 0.5,
	\amp, Pfunc({ rrand(0.15, 0.3) })
).play;
)
// While it plays, re-evaluate with a different \scale: Scale.dorian, Scale.phrygian,
// Scale.major. Same degrees, new mood, zero rewriting.
// ~p4.stop;

// ============ 6. COMBINING: Ppar plays patterns together ============
(
~song = Ppar([
	Pbind(\instrument, \patBass, \midinote, Pseq([36, 36, 43, 41], inf), \dur, 0.5),
	Pbind(\instrument, \patHat, \dur, Pseq([0.25, 0.25, 0.5], inf), \amp, 0.1),
	Pbind(\instrument, \patPluck, \midinote, Prand([60, 64, 67, 72], inf),
		\dur, Pseq([0.25, 0.5], inf), \amp, 0.12)
]).play;
)
// ~song.stop;  (cousin Ptpar staggers start times: Ptpar([0, patA, 2, patB]).play)

// ============ 7. LIVE CODING: Pdef + Pbindef swap code mid-performance ============
(
Pdef(\bass, Pbind(\instrument, \patBass, \midinote, Pseq([36, 43, 41, 43], inf), \dur, 0.5)).play;
)
// While it plays, evaluate ONLY this line: the bassline swaps, the beat never stops.
Pbindef(\bass, \midinote, Pseq([36, 48, 43, 46], inf));
// And back: Pbindef(\bass, \midinote, Pseq([36, 43, 41, 43], inf));
// Pdef(\bass).stop;  Pdef.clear;  (always clear your proxies when done)

// Tdef is the same idea for TASKS (plain Routines you redefine live):
(
Tdef(\tock, { loop({ "tock".postln; 1.wait; }) }).play;
Tdef(\tick, { loop({ "  tick".postln; 0.5.wait; }) }).play;
)
// Tdef(\tock).stop;  Tdef(\tick).stop;  Tdef.clear;

// ============ 8. DEMAND UGENS: patterns inside a single synth ============
// Same Dseq idea as the language-side patterns, but evaluated by the SERVER,
// so timing is sample-accurate. Compare with Pbind (language-side, ~ms timing).
(
~d = Synth(\dseqDemo);
)
// ~d.free;

// ============ 9. FULL TOUR: every technique back to back ============
(
~tour = {
	Routine({
		var p;
		"Tour 1/5: Pseq melody accelerated by the clock.".postln;
		TempoClock.default.tempo = 2;
		p = Pbind(\instrument, \patPluck, \midinote, Pseq([60, 64, 67, 72], inf), \dur, 0.25).play;
		6.wait; p.stop;
		"Tour 2/5: weighted random + drunk-walk dynamics.".postln;
		p = Pbind(\instrument, \patPluck, \midinote, Prand([60, 64, 67, 72, 76], inf),
			\dur, Pwrand([0.25, 0.5], [0.7, 0.3], inf), \amp, Pbrown(0.05, 0.3, 0.05, inf)).play;
		8.wait; p.stop;
		"Tour 3/5: full band via Ppar.".postln;
		p = Ppar([
			Pbind(\instrument, \patBass, \midinote, Pseq([36, 36, 43, 41], inf), \dur, 0.5),
			Pbind(\instrument, \patHat, \dur, 0.25, \amp, 0.08)
		]).play;
		8.wait; p.stop;
		"Tour 4/5: live swap via Pdef (listen for the bassline change).".postln;
		Pdef(\tourBass, Pbind(\instrument, \patBass, \midinote, Pseq([36, 43, 41, 43], inf), \dur, 0.5)).play;
		4.wait;
		Pbindef(\tourBass, \midinote, Pseq([36, 48, 43, 46], inf));
		4.wait; Pdef(\tourBass).stop;
		"Tour 5/5: Demand UGen inside one synth.".postln;
		p = Synth(\dseqDemo);
		6.wait; p.free;
		TempoClock.default.tempo = 1;
		"Tour done. ~stopAll.() tidies everything.".postln;
	}).play;
};
"Tour loaded: run ~tour.() .".postln;
)
