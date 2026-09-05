// Soothing Ambient Drone
// Usage: open in SuperCollider IDE and evaluate the whole block (Cmd/Ctrl+A, Cmd/Ctrl+Enter).
// Stop with Cmd+. (stops all sound) or: ~stop.()

(
s.waitForBoot({

	// --- Tweakables ---
	~chordTime = 24;   // seconds per chord
	~masterVol = 0.8;  // overall level
	~cutoff    = 600;  // base lowpass cutoff (Hz), lower = darker/calmer
	~verbMix   = 0.6;  // 0-1 wet amount
	~verbRoom  = 0.85; // 0-1 room size

	// Slow-evolving chord progression (MIDI notes). A-minor-ish / modal, no leading tones.
	~chords = [
		[33, 45, 52, 57, 60, 64],  // A1 A2 E3 A3 C4 E4
		[29, 41, 48, 53, 57, 60],  // F1 F2 C3 F3 A3 C4
		[31, 43, 50, 55, 59, 62],  // G1 G2 D3 G3 B3 D4
		[33, 45, 52, 55, 60, 64],  // A1 A2 E3 G3 C4 E4 (Am7)
		[26, 38, 45, 50, 55, 59],  // D1 D2 A2 D3 G3 B3
		[31, 43, 50, 57, 60, 65]   // G1 G2 D3 A3 C4 F4
	];

	// Buses
	~droneBus = Bus.audio(s, 2);

	// --- One warm, slowly-breathing pad voice ---
	SynthDef(\padVoice, { |freq = 110, amp = 0.08, cutoff = 600, atk = 6, rel = 8, pan = 0, out = 0|
		var osc, filt, env, lfo, sig;
		// Gentle detuned stack: 2 saws + sine sub, very quiet beating
		osc = Mix([
			Saw.ar(freq * 1.001),
			Saw.ar(freq * 0.999),
			SinOsc.ar(freq * 0.5, 0, 0.6)
		]) * 0.33;
		// Slow filter wander for "breathing" feel
		lfo = SinOsc.kr(0.05 + Rand(0.0, 0.06), Rand(0, 6.28)).range(0.75, 1.35);
		filt = LPF.ar(osc, (cutoff * lfo).clip(80, 4000));
		// Slow fade in/out; doneAction frees the synth
		env = EnvGen.kr(Env.linen(atk, 12, rel, 1, -4), doneAction: 2);
		sig = filt * env * amp;
		// Slow stereo drift
		sig = Pan2.ar(sig, SinOsc.kr(0.07 + Rand(0.0, 0.05), Rand(0, 6.28), 0.7, pan).clip(-1, 1));
		Out.ar(out, sig);
	}).add;

	// --- Airy noise wash (soft hiss, no harshness) ---
	SynthDef(\wash, { |amp = 0.015, cutoff = 900, atk = 10, rel = 10, out = 0|
		var noise, filt, env;
		noise = PinkNoise.ar(1);
		filt = LPF.ar(noise, SinOsc.kr(0.04, 0, 250, cutoff).clip(100, 3000));
		env = EnvGen.kr(Env.linen(atk, 12, rel, 1, -4), doneAction: 2);
		Out.ar(out, Pan2.ar(filt * env * amp, 0));
	}).add;

	// --- Reverb return: reads drone bus, writes to hardware out ---
	SynthDef(\droneVerb, { |in = 0, mix = 0.6, room = 0.85, amp = 0.8|
		var dry, wet;
		dry = In.ar(in, 2);
		wet = FreeVerb2.ar(dry[0], dry[1], mix, room, 0.5);
		Out.ar(0, wet * amp);
	}).add;

	s.sync;

	// Start reverb (stays up; free with ~verb.free)
	~verb = Synth(\droneVerb, [\in, ~droneBus, \mix, ~verbMix, \room, ~verbRoom, \amp, ~masterVol]);
	s.sync;

	// Chord sequencer: crossfade one chord into the next
	~seqRoutine = Routine({
		var idx = 0;
		loop {
			var chord = ~chords[idx % ~chords.size];
			("Playing chord " ++ (idx % ~chords.size) ++ ": " ++ chord).postln;
			chord.do({ |mid, i|
				Synth(\padVoice, [
					\freq, mid.midicps * [1, 1.002].choose,
					\amp, 0.06 + rrand(0.0, 0.04),
					\cutoff, ~cutoff * rrand(0.8, 1.4),
					\atk, rrand(5.0, 9.0),
					\rel, rrand(7.0, 12.0),
					\pan, rrand(-0.5, 0.5),
					\out, ~droneBus
				]);
				// Stagger entries so the chord blooms instead of hitting at once
				rrand(0.5, 2.5).wait;
			});
			// One soft wash per chord change
			Synth(\wash, [\amp, 0.012, \cutoff, ~cutoff * 1.5, \out, ~droneBus]);
			(~chordTime).wait;
			idx = idx + 1;
		}
	}).play;

	// Stop function
	~stop = {
		~seqRoutine.stop;
		~verb.free;
		"Drone stopped.".postln;
	};


	"Soothing drone playing. Run ~stop.() or press Cmd+. to stop.".postln;
});
)
