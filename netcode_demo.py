#!/usr/bin/env python3
"""
netcode_demo.py - client-side prediction, server reconciliation and
entity interpolation, simulated over a fake laggy network.

No dependencies; runs in Termux:   python netcode_demo.py
Options:  --latency 150  --jitter 40  --loss 0.05  --seed 1

What's simulated
----------------
* An authoritative SERVER running car physics at 30 ticks/s.
* YOUR car: the client sends inputs (throttle), the server applies them.
  The server also applies random "explosion" shoves the client can't foresee,
  so the client's prediction is sometimes wrong and must be corrected.
* An ENEMY car driven by the server, which the client only sees via snapshots.
* A NETWORK with one-way latency, random jitter and packet loss.

It runs the same match under three client strategies for your own car:
  1. naive      - just draw the last server snapshot (feels laggy)
  2. predict    - apply inputs locally, never correct (drifts from the truth)
  3. reconcile  - predict, then on each snapshot rewind to the server state,
                  replay unacknowledged inputs, and smooth out the difference
and two strategies for the enemy car:
  a. raw        - draw the newest snapshot (jerky)
  b. interp     - draw 100 ms in the past, blending two snapshots (smooth)
"""
import argparse
import heapq
import math
import random

TICK_HZ = 30
DT = 1.0 / TICK_HZ
ACCEL = 12.0      # m/s^2 at full throttle
DRAG = 0.98       # velocity multiplier per tick


# ---------------------------------------------------------------- physics
def step(x, v, throttle):
    """One tick of deterministic car physics (shared by client and server)."""
    v = (v + throttle * ACCEL * DT) * DRAG
    return x + v * DT, v


def throttle_at(tick):
    """The player's driving: accelerate, coast, reverse, accelerate again."""
    t = tick * DT
    if t < 0.5:
        return 0.0
    if t < 3.0:
        return 1.0
    if t < 4.0:
        return 0.0
    if t < 6.0:
        return -1.0
    return 0.6


def enemy_pos(tick):
    """The server moves the enemy along a smooth curve."""
    t = tick * DT
    return 20 * math.sin(t * 0.9) + 3 * math.sin(t * 3.1)


# ---------------------------------------------------------------- network
class Network:
    """One-way pipe with latency, jitter and loss. Times are in seconds."""

    def __init__(self, latency_ms, jitter_ms, loss, rng):
        self.lat = latency_ms / 1000
        self.jit = jitter_ms / 1000
        self.loss = loss
        self.rng = rng
        self.q = []
        self.n = 0

    def send(self, now, msg):
        if self.rng.random() < self.loss:
            return  # dropped
        delay = self.lat + self.rng.uniform(0, self.jit)
        self.n += 1
        heapq.heappush(self.q, (now + delay, self.n, msg))

    def receive(self, now):
        out = []
        while self.q and self.q[0][0] <= now:
            out.append(heapq.heappop(self.q)[2])
        return out


# ---------------------------------------------------------------- server
class Server:
    def __init__(self, rng):
        self.x, self.v = 0.0, 0.0
        self.pending = []          # inputs received, not yet applied
        self.last_seq = -1         # last input applied
        self.last_throttle = 0.0
        self.rng = rng
        self.shoves = []           # (tick, impulse) for reporting
        self.x_after_seq = {}      # server position right after input seq N

    def tick(self, tick):
        # Apply at most one input per tick, in order. If an input is late,
        # repeat the last one (the client will be corrected afterwards).
        self.pending.sort(key=lambda m: m["seq"])
        while self.pending and self.pending[0]["seq"] <= self.last_seq:
            self.pending.pop(0)    # duplicate / too old
        if self.pending:
            inp = self.pending.pop(0)
            self.last_seq = inp["seq"]
            self.last_throttle = inp["throttle"]
        self.x, self.v = step(self.x, self.v, self.last_throttle)
        self.x_after_seq.setdefault(self.last_seq, self.x)

        # Something the client can't predict: an explosion shoves the car.
        if tick > 30 and self.rng.random() < 0.02:
            impulse = self.rng.choice([-1, 1]) * self.rng.uniform(3, 6)
            self.v += impulse
            self.shoves.append((tick, impulse))

        return {"tick": tick, "ack": self.last_seq, "x": self.x, "v": self.v,
                "enemy": enemy_pos(tick)}


# ---------------------------------------------------------------- clients
class Client:
    def __init__(self, mode):
        self.mode = mode           # naive | predict | reconcile
        self.x, self.v = 0.0, 0.0  # predicted (or last snapshot) state
        self.unacked = []          # inputs the server hasn't confirmed yet
        self.smooth = 0.0          # visual offset left over after a correction
        self.snaps = []            # enemy snapshots: (server_time, pos)
        self.corrections = 0

    def local_input(self, seq, throttle):
        if self.mode == "naive":
            return
        self.unacked.append((seq, throttle))
        self.x, self.v = step(self.x, self.v, throttle)

    def on_snapshot(self, s):
        self.snaps.append((s["tick"] * DT, s["enemy"]))
        self.snaps = self.snaps[-20:]
        if self.mode == "naive":
            self.x, self.v = s["x"], s["v"]
        elif self.mode == "reconcile":
            old_x = self.x
            # Rewind to the authoritative state...
            x, v = s["x"], s["v"]
            # ...drop inputs it has already applied...
            self.unacked = [(q, t) for q, t in self.unacked if q > s["ack"]]
            # ...and replay the rest on top.
            for _, t in self.unacked:
                x, v = step(x, v, t)
            self.x, self.v = x, v
            err = old_x - self.x
            if abs(err) > 0.01:
                self.corrections += 1
            self.smooth += err     # hide the snap, fade it out below
        # "predict" mode ignores the server for its own car

    def display_x(self):
        self.smooth *= 0.85        # bleed off ~15% of the error per frame
        return self.x + self.smooth

    def enemy_raw(self):
        return self.snaps[-1][1] if self.snaps else 0.0

    def enemy_interp(self, now, delay):
        """Draw the enemy `delay` seconds in the past between two snapshots."""
        t = now - delay
        s = sorted(self.snaps)
        for (t0, p0), (t1, p1) in zip(s, s[1:]):
            if t0 <= t <= t1:
                return p0 + (p1 - p0) * (t - t0) / (t1 - t0)
        if s and t > s[-1][0] and len(s) >= 2:   # ran out: extrapolate
            (t0, p0), (t1, p1) = s[-2], s[-1]
            return p1 + (p1 - p0) / (t1 - t0) * (t - t1)
        return s[-1][1] if s else 0.0


# ---------------------------------------------------------------- match
def run(mode, args):
    rng = random.Random(args.seed)              # same network + shoves each run
    up = Network(args.latency, args.jitter, args.loss, rng)
    down = Network(args.latency, args.jitter, args.loss, rng)
    server = Server(random.Random(args.seed + 99))
    client = Client(mode)

    n_ticks = int(args.seconds * TICK_HZ)
    interp_delay = 0.1 + args.jitter / 1000      # 100 ms + jitter allowance
    rows, disps, raws, ints = [], [], [], []
    first_move = None

    for tick in range(n_ticks):
        now = tick * DT
        # client: read input, predict, send
        thr = throttle_at(tick)
        client.local_input(tick, thr)
        up.send(now, {"seq": tick, "throttle": thr})
        # server: apply arrived inputs, simulate, broadcast
        server.pending += up.receive(now)
        snap = server.tick(tick)
        down.send(now, snap)
        # client: process arrived snapshots, render
        for s in down.receive(now):
            client.on_snapshot(s)
        disp = client.display_x()
        raw = client.enemy_raw()
        intp = client.enemy_interp(now, interp_delay)

        if first_move is None and abs(disp) > 1e-6:
            first_move = now
        disps.append(disp)
        raws.append(raw)
        ints.append(intp)
        if tick % 15 == 0:
            rows.append((now, thr, server.x, disp))

    # Fair comparison for your car: what you see after pressing input N
    # versus where the server actually put you after applying input N.
    # (Predicting ahead of the server is the point, so comparing against the
    # server's *current* position would just measure the network delay.)
    truth = server.x_after_seq
    own_err = [abs(d - truth[k]) for k, d in enumerate(disps) if k in truth]

    def roughness(xs):
        """Biggest change in per-frame movement (1 frame of 'stutter')."""
        xs = xs[TICK_HZ:]          # ignore the first second (no data yet)
        steps = [b - a for a, b in zip(xs, xs[1:])]
        return max(abs(b - a) for a, b in zip(steps, steps[1:]))

    true_enemy = [enemy_pos(k) for k in range(n_ticks)]
    lag = round(interp_delay * TICK_HZ)

    return {
        "mode": mode, "rows": rows, "client": client, "server": server,
        "response_ms": ((first_move - 0.5) * 1000) if first_move else None,
        "own_err": sum(own_err) / len(own_err), "own_err_max": max(own_err),
        "own_rough": roughness(disps),
        "en_true_rough": roughness(true_enemy),
        "en_raw_rough": roughness(raws), "en_int_rough": roughness(ints),
        "en_delay_ms": interp_delay * 1000,
        "en_int_err": sum(abs(ints[k] - true_enemy[k - lag])
                          for k in range(lag + 30, n_ticks)) / (n_ticks - lag - 30),
    }


def ascii_track(server_x, client_x, lo=-15, hi=45, width=50):
    """S = true server position, C = what the client draws, * = both."""
    def col(x):
        return max(0, min(width - 1, int((x - lo) / (hi - lo) * (width - 1))))
    line = ["."] * width
    cs, cc = col(server_x), col(client_x)
    line[cs] = "S"
    line[cc] = "*" if cc == cs else "C"
    return "".join(line)


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--latency", type=float, default=120, help="one-way ms")
    p.add_argument("--jitter", type=float, default=40, help="extra random ms")
    p.add_argument("--loss", type=float, default=0.05, help="packet loss 0..1")
    p.add_argument("--seconds", type=float, default=9)
    p.add_argument("--seed", type=int, default=1)
    args = p.parse_args()

    print(f"Network: {args.latency:.0f} ms one way (+0..{args.jitter:.0f} ms jitter), "
          f"{args.loss:.0%} loss, server {TICK_HZ} Hz\n")
    results = [run(m, args) for m in ("naive", "predict", "reconcile")]

    shoves = results[0]["server"].shoves
    if shoves:
        print("Explosions the client couldn't predict at: " +
              ", ".join(f"{t * DT:.1f}s ({i:+.1f} m/s)" for t, i in shoves) + "\n")

    for r in results:
        print(f"=== {r['mode']} ===   S = server right now, C = what you see "
              "(with prediction, C runs ahead of S by the lag)")
        for now, thr, sx, cx in r["rows"]:
            print(f" {now:4.1f}s thr {thr:+.1f}  {ascii_track(sx, cx)}  "
                  f"gap {abs(cx - sx):5.2f} m")
        print()

    print("YOUR CAR                    naive    predict  reconcile")
    def row(label, key, fmt):
        print(f"  {label:<24}" + "".join(fmt.format(r[key]) for r in results))
    row("response to input (ms)", "response_ms", "{:9.0f}")
    row("mean error (m)", "own_err", "{:9.2f}")
    row("worst error (m)", "own_err_max", "{:9.2f}")
    row("worst stutter (m/frame)", "own_rough", "{:9.2f}")
    print("  error = where you're drawn after input N vs where the server put you")
    rc = results[2]["client"].corrections
    print(f"  (reconcile made {rc} corrections, smoothed over a few frames)\n")

    r = results[2]
    print("ENEMY CAR                   truth     raw    interp")
    print(f"  worst stutter (m/frame)  {r['en_true_rough']:7.2f} {r['en_raw_rough']:7.2f}"
          f" {r['en_int_rough']:8.2f}")
    print(f"  interp draws the enemy {r['en_delay_ms']:.0f} ms in the past, "
          f"tracking that path within {r['en_int_err']:.2f} m on average.")
    print("  Interpolation trades a little extra delay for smooth movement;\n"
          "  that delay is what server-side lag compensation rewinds for.")


if __name__ == "__main__":
    main()
