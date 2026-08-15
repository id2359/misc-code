#!/usr/bin/env python3
"""
OLYMPICA -- The U.N. Raid on Mars, 2206 A.D.
Metagaming MicroGame 7 (Lynn Willis, 1978)

Single-file playable implementation of the INTRODUCTORY SCENARIO.
You command the U.N. raiders; the computer plays the Web (defender).

Implemented rules (from the rulebook, sections noted):
  * 4 Game-Turns (4.1).  Forces: Web = 1 Generator, 2 Strongpoints,
    10 Web Infantry, 3 dummies; U.N. = 3 Laser Tanks, 9 Heavy Infantry,
    3 Light Infantry.  No tunnels / BOAR / lifters in this scenario.
  * Turn sequence (6.0): Web (compulsion, reinforcement, movement+close
    assault, ranged combat, DUST removal) then U.N. (drops, movement+CA,
    ranged combat, DUST removal, light-infantry second movement).
  * Hidden setup: Web counters are placed face-down ('??'); revealed only
    when they move, fire, or are attacked (5.2).  Dummies (20.0).
  * Zone of uncertainty: hexagon 5 hexes across; the Generator is in it.
  * Movement (7.0): U.N. units stop on entering incline/cliff; Web
    infantry ignore terrain.  Avalanche: U.N. unit entering a cliff hex
    dies on a die roll of 6 (7.4.3), rolled before close assaults.
  * No zones of control (8.0); one real unit per hex, the Generator and
    dummies do not count for stacking (9.0).
  * Ranged combat (10.0): combine attackers on one defender, odds rounded
    in the defender's favor, clamped 1-3 .. 4-1, CRT roll.  Cliff hexes
    halve CS (round up); DUST halves CS (never quartered with cliff).
  * Close assault (11.0): defender rolls first on the 4-1 column against
    the assaulter; die passes over on a 1 (DUST is ignored in CA);
    continues until a unit is removed from the hex.  Dummies are removed
    on contact; a lone Generator is captured.  A unit may be close
    assaulted only once per Movement Phase; CA ends the assaulter's move.
  * Combat results (12.0) incl. retreats chosen by the opposing player,
    DUST (halved CS, no movement until removed in own DUST phase), EX
    exchange with printed-strength matching, and the no-adverse-result
    exceptions of 12.1/16.1 (tank/strongpoint vs infantry; strongpoint
    vs tank at 7 hexes; strongpoints never retreat and ignore DUST).
  * Drops (14.0): sticks of 3 mutually adjacent units; may land on Web
    counters (reveal + close assault); cliff landing = avalanche on a 6;
    dropped units may not move that turn but may fire; drop compulsion
    (14.2/19.1): one drop per Drop Phase landing within 2 hexes of the
    Generator may be displaced up to 3 hexes, formation kept.
  * Light infantry (15.0) move again after the U.N. Ranged Combat Phase.
  * Movement compulsion (19.2): each Web turn one U.N. unit may be moved
    up to 3 hexes (never onto units, never off-map, cliff avalanches
    apply, never cliff-to-cliff).  Compulsion is broken forever once a
    U.N. unit ends the U.N. turn stacked with the Generator (19.3).
  * Web reinforcements (21.0): up to 4 previously eliminated Web
    Infantry per Web turn, east edge on odd turns, west on even.
  * Victory (4.1): U.N. wins if stacked with the Generator at the end of
    Game-Turn 4; draw if it stacked at some time but not at the end;
    Web wins otherwise.

Approximations (unavoidable from the scanned map): the hex map is a
26 x 23 grid with terrain (clear / incline / cliff) hand-placed to match
the printed map's shape -- Nix Olympica's caldera rim in the south-east
quadrant, the cliff belt on the east edge, a ridge in the north-west --
but it is not hex-for-hex identical to the paper map.  The CRT used is
the map-sheet printing (it matches the worked example in rule 11.0).

Usage:  python3 olympica.py [--seed N] [--selftest [GAMES]]
"""

import random
import sys

# ----------------------------------------------------------------------
# Hex geometry.  Labels are CCRR (column 01-26 west->east,
# row 01-23 north->south).  Odd-q offset -> axial coordinates.
# ----------------------------------------------------------------------

COLS, ROWS = 26, 23


def lab(c, r):
    return f"{c:02d}{r:02d}"


def unlab(h):
    return int(h[:2]), int(h[2:])


def on_map(c, r):
    return 1 <= c <= COLS and 1 <= r <= ROWS


ALL_HEXES = [lab(c, r) for c in range(1, COLS + 1) for r in range(1, ROWS + 1)]


def to_axial(h):
    c, r = unlab(h)
    return c, r - (c - (c & 1)) // 2


AX_DIRS = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]


def from_axial(q, ar):
    r = ar + (q - (q & 1)) // 2
    return (q, r) if on_map(q, r) else None


def neighbors(h):
    q, ar = to_axial(h)
    out = []
    for dq, dr in AX_DIRS:
        cr = from_axial(q + dq, ar + dr)
        if cr:
            out.append(lab(*cr))
    return out


def hex_dist(a, b):
    q1, r1 = to_axial(a)
    q2, r2 = to_axial(b)
    dq, dr = q1 - q2, r1 - r2
    return (abs(dq) + abs(dr) + abs(dq + dr)) // 2


def hexes_within(center, n):
    return [h for h in ALL_HEXES if hex_dist(h, center) <= n]


def hex_ring(center, n):
    return [h for h in ALL_HEXES if hex_dist(h, center) == n]


# ----------------------------------------------------------------------
# Map terrain (approximation of the printed map -- see module docstring)
# ----------------------------------------------------------------------

ZONE_CENTER = "1413"
ZONE = set(hexes_within(ZONE_CENTER, 2))          # hexagon five hexes across

CALDERA = "2019"                                   # Nix Olympica caldera

_CLIFFS = {
    # east-edge cliff belt
    "2601", "2602", "2603", "2605", "2606", "2608", "2609", "2611",
    "2612", "2614", "2502", "2504", "2507", "2510", "2513",
    # north-west ridge crest
    "0102", "0202", "0203", "0303",
    # caldera north rim outcrops
    "1815", "1915", "2015",
    # south-west corner
    "0221", "0322", "0422", "0223",
}

_INCLINES = set()
_INCLINES |= set(hex_ring(CALDERA, 3)) | set(hex_ring(CALDERA, 2))  # rim
_INCLINES |= {
    # north-west ridge flanks
    "0304", "0404", "0505", "0605", "0706", "0806",
    # broken ground west of the zone of uncertainty
    "1009", "1010", "1110", "0911", "1012",
    # east approach slopes below the cliff belt
    "2303", "2405", "2308", "2410", "2312", "2413",
    # left-centre gullies
    "0614", "0715", "0616", "0517", "0818",
    # south arcs outside the caldera
    "1521", "1622", "1420",
}
_INCLINES -= _CLIFFS

TERRAIN = {}
for _h in ALL_HEXES:
    TERRAIN[_h] = "cliff" if _h in _CLIFFS else (
        "incline" if _h in _INCLINES else "clear")

# ----------------------------------------------------------------------
# Combat Results Table (map-sheet printing; matches the 11.0 example)
# ----------------------------------------------------------------------

CRT_COLS = ["1-3", "1-2", "1-1", "2-1", "3-1", "4-1"]
CRT = {
    "1-3": ["AE", "AE", "AE", "AE", "AR2", "DUST"],
    "1-2": ["AE", "EX", "AR2", "DUST", "DUST", "DR2"],
    "1-1": ["EX", "AR2", "DUST", "DUST", "DR2", "EX"],
    "2-1": ["AR2", "DUST", "DUST", "DR2", "EX", "DE"],
    "3-1": ["DUST", "DUST", "DUST", "DR2", "EX", "DE"],
    "4-1": ["DUST", "DR2", "EX", "DE", "DE", "DE"],
}


def odds_column(atk, dfn):
    """Odds ratio rounded in the defender's favor, clamped 1-3..4-1 (10.1)."""
    if atk >= dfn:
        k = min(atk // dfn, 4)
        return f"{k}-1"
    k = -(-dfn // atk)                     # ceil, e.g. 24 vs 25 -> 1-2
    return f"1-{min(k, 3)}"


# ----------------------------------------------------------------------
# Units
# ----------------------------------------------------------------------

STATS = {  # kind: (name, combat strength, range, movement factor)
    "HI":  ("U.N. Heavy Infantry", 10, 2, 3),
    "LI":  ("U.N. Light Infantry",  6, 2, 3),
    "LT":  ("U.N. Laser Tank",     25, 6, 2),
    "WI":  ("Web Infantry",         8, 2, 3),
    "SP":  ("Web Strongpoint",     30, 7, 0),
    "GEN": ("Web Generator",        0, 0, 0),
    "DUM": ("Web Dummy",            0, 0, 0),
}


class Unit:
    def __init__(self, uid, side, kind):
        self.uid, self.side, self.kind = uid, side, kind
        self.name, self.cs, self.rng, self.mf = STATS[kind]
        self.pos = None            # hex label, or None (dead / undropped)
        self.alive = True
        self.face_up = side == "UN"
        self.dusted = False
        self.dropped_turn = None   # game-turn it dropped (no move that turn)
        self.setup_drop = False    # dropped during initial setup (14.4 exception)
        self.compelled_this_turn = False
        self.fired = False
        self.moved = False

    @property
    def real(self):               # counts for stacking / can fight
        return self.kind not in ("GEN", "DUM")

    @property
    def infantry(self):
        return self.kind in ("HI", "LI", "WI")

    def eff_cs(self, game):
        """Printed CS halved (round up) by cliff hex and/or DUST -- but
        never quartered (12.5)."""
        cs = self.cs
        if cs and ((self.pos and TERRAIN[self.pos] == "cliff") or self.dusted):
            cs = -(-cs // 2)
        return cs

    def __repr__(self):
        return f"{self.uid}@{self.pos}"


# ----------------------------------------------------------------------
# The Game engine
# ----------------------------------------------------------------------

class Game:
    def __init__(self, seed=None):
        self.rng = random.Random(seed)
        self.turn = 1
        self.turn_side = "Web"
        self.units = []
        self.log = []
        self._log_ptr = 0
        self.ever_stacked = False
        self.result = None
        self.setup_done = False
        self._build_units()

    def _build_units(self):
        for k, n in [("HI", 9), ("LI", 3), ("LT", 3)]:
            for i in range(n):
                self.units.append(Unit(f"{k}{i+1}", "UN", k))
        for i in range(10):
            self.units.append(Unit(f"WI{i+1}", "Web", "WI"))
        for i in range(2):
            self.units.append(Unit(f"SP{i+1}", "Web", "SP"))
        for i in range(3):
            self.units.append(Unit(f"D{i+1}", "Web", "DUM"))
        self.gen = Unit("GEN", "Web", "GEN")
        self.units.append(self.gen)

    # -- queries --------------------------------------------------------
    def find(self, uid):
        for u in self.units:
            if u.uid == uid:
                return u
        return None

    def alive_units(self, side=None, real_only=False):
        r = [u for u in self.units if u.alive and (side is None or u.side == side)]
        return [u for u in r if u.real] if real_only else r

    def units_at(self, h):
        return [u for u in self.units if u.alive and u.pos == h]

    def unit_at(self, h, side=None, real_only=True):
        for u in self.units_at(h):
            if (side is None or u.side == side) and (not real_only or u.real):
                return u
        return None

    def occupant_blocking(self, h, mover_side):
        """The enemy unit that triggers a Close Assault if `mover_side`
        enters hex h (hidden Web units/dummies block identically to
        revealed ones -- the mover can't yet tell). The Generator alone
        never blocks (19.5)."""
        for u in self.units_at(h):
            if u.side != mover_side and u.kind != "GEN":
                return u
        return None

    def friendly_real_at(self, h, side):
        u = self.unit_at(h, side=side, real_only=True)
        return u

    def ignores_terrain(self, unit):
        # Web Infantry movement is unaffected by incline/cliff (7.4.2/7.4.3).
        return unit.side == "Web" and unit.infantry

    def can_move_this_phase(self, unit):
        if unit.dusted:
            return False
        if getattr(unit, "compelled_this_turn", False) and unit.side == "UN" \
                and self.turn_side == "UN":
            return False
        if unit.dropped_turn == self.turn and not getattr(unit, "setup_drop", False):
            return False
        return True

    # -- pathing ----------------------------------------------------------
    def reachable(self, unit, mf=None, ignore_terrain_stop=False, allow_enemy_stop=True):
        """BFS -> {hex: path} of every hex the unit could end movement in,
        given up to `mf` hexes (defaults to the unit's Movement Factor)."""
        if mf is None:
            mf = unit.mf
        start = unit.pos
        results = {}
        seen = {start}
        frontier = [(start, [start], 0)]
        while frontier:
            h, path, cost = frontier.pop(0)
            if h != start:
                results[h] = path
            if cost >= mf:
                continue
            if h != start and allow_enemy_stop and self.occupant_blocking(h, unit.side):
                continue   # a Close Assault ends movement here
            terrain_stop = (not ignore_terrain_stop and not self.ignores_terrain(unit)
                             and h != start and TERRAIN[h] in ("incline", "cliff"))
            if terrain_stop:
                continue
            for nb in neighbors(h):
                if nb in seen:
                    continue
                if self.friendly_real_at(nb, unit.side):
                    continue
                seen.add(nb)
                frontier.append((nb, path + [nb], cost + 1))
        return results

    # -- core actions -----------------------------------------------------
    def kill(self, unit):
        if not unit.alive:
            return
        prev = unit.pos
        unit.alive = False
        unit.pos = None
        self.log.append(f"  {unit.name} ({unit.uid}) eliminated" +
                         (f" at {prev}" if prev else ""))

    def retreat_unit(self, unit, depth=0):
        if not unit.alive or unit.pos is None:
            return
        if unit.kind == "SP" or unit.mf == 0:
            self.log.append(f"  {unit.uid} cannot retreat (immobile) -- ignored.")
            return
        orig = unit.pos
        ring = [h for h in hex_ring(orig, 2)]
        empties = [h for h in ring if self.unit_at(h) is None]
        if empties:
            dest = self.rng.choice(empties)
            unit.pos = dest
            self.log.append(f"  {unit.uid} retreats to {dest}")
            return
        enemy_occ = [h for h in ring if self.unit_at(h) and self.unit_at(h).side != unit.side]
        if enemy_occ and depth < 3:
            dest = self.rng.choice(enemy_occ)
            unit.pos = dest
            self.log.append(f"  {unit.uid} forced to retreat into {dest} -- Close Assault!")
            blocker = self.occupant_blocking(dest, unit.side)
            if blocker:
                self.close_assault(unit, blocker)
            return
        self.log.append(f"  {unit.uid} has no legal retreat hex -- eliminated.")
        self.kill(unit)

    def close_assault(self, mover, defender):
        """11.0/12.6.  The hex's original occupant rolls first on the 4-1
        column; a die of 1 is DUST, always ignored, and the die passes to
        the other unit.  Because column 4-1 never contains AE or AR2, the
        current roller can never be hurt by its own roll -- only the
        'other' unit can be retreated/eliminated, or both on an EX."""
        defender.face_up = True
        if defender.kind == "DUM":
            self.log.append(f"  {mover.uid} Close Assaults {defender.uid} -- it was a dummy, removed.")
            defender.alive = False
            defender.pos = None
            return
        roller, other = defender, mover
        for _ in range(50):
            d = self.rng.randint(1, 6)
            res = CRT["4-1"][d - 1]
            self.log.append(f"  Close Assault: {roller.uid} rolls {d} -> {res}")
            if res == "DUST":
                roller, other = other, roller
                continue
            if res == "DR2":
                if other.kind == "SP" or other.mf == 0:
                    self.log.append(f"  {other.uid} ignores forced retreat (immobile).")
                    roller, other = other, roller
                    continue
                self.retreat_unit(other)
                return
            if res == "EX":
                self.kill(mover)
                self.kill(defender)
                return
            if res == "DE":
                self.kill(other)
                return
        self.log.append("  Close Assault inconclusive after 50 rounds -- stalemate broken, no result.")

    def move_unit(self, unit, dest):
        if unit.side == "UN" and TERRAIN[dest] == "cliff":
            if self.rng.randint(1, 6) == 6:
                self.log.append(f"  Avalanche! {unit.uid} destroyed entering {dest}.")
                self.kill(unit)
                return
        blocker = self.occupant_blocking(dest, unit.side)
        unit.pos = dest
        unit.moved = True
        if unit.side == "Web":
            unit.face_up = True
        if blocker:
            self.close_assault(unit, blocker)

    # -- ranged combat ------------------------------------------------------
    def can_target(self, attacker, defender):
        if not attacker.alive or not defender.alive:
            return False
        if attacker.pos is None or defender.pos is None:
            return False
        if attacker.side == defender.side or attacker.cs == 0 or defender.kind == "GEN":
            return False
        return hex_dist(attacker.pos, defender.pos) <= attacker.rng

    def ranged_attack(self, attackers, defender):
        for a in attackers:
            a.fired = True
            if a.side == "Web":
                a.face_up = True
        defender.face_up = True
        cs = sum(a.eff_cs(self) for a in attackers)
        dcs = defender.eff_cs(self)
        col = odds_column(cs, dcs)
        d = self.rng.randint(1, 6)
        res = CRT[col][d - 1]
        vs_infantry = defender.infantry
        only_lt_sp = all(a.kind in ("LT", "SP") for a in attackers)
        sp_max_range = all(a.kind == "SP" and hex_dist(a.pos, defender.pos) == 7 for a in attackers)
        note = ""
        if res in ("AE", "AR2", "EX") and only_lt_sp and vs_infantry:
            note = " (ignored: Laser Tank/Strongpoint vs infantry, 16.1)"
            res = "NE"
        if res in ("AE", "EX") and sp_max_range:
            note = " (ignored: Strongpoint firing at 7-hex range, 16.1)"
            res = "NE"
        if res == "DR2" and defender.kind == "SP":
            note = " (ignored: Strongpoint cannot retreat, 12.3.2)"
            res = "NE"
        if res == "DUST" and defender.kind == "SP":
            note = " (ignored: Strongpoint ignores DUST, 12.5/16.1)"
            res = "NE"
        self.log.append(f"  Ranged: {[a.uid for a in attackers]} (CS {cs}) -> "
                         f"{defender.uid} (CS {dcs}) odds {col}, die {d}: {res}{note}")
        if res == "AE":
            for a in attackers:
                self.kill(a)
        elif res == "DE":
            self.kill(defender)
        elif res == "AR2":
            for a in attackers:
                self.retreat_unit(a)
        elif res == "DR2":
            self.retreat_unit(defender)
        elif res == "EX":
            for a in attackers:
                self.kill(a)
            self.kill(defender)
        elif res == "DUST":
            defender.dusted = True

    # -- drops ------------------------------------------------------------
    def drop_triangle(self, anchor, dirn):
        """The 3 mutually-adjacent hexes of a legal drop (14.1): the anchor
        plus its two neighbors at consecutive compass directions, which are
        themselves always adjacent to one another."""
        nbrs = neighbors(anchor)
        if len(nbrs) < 6:
            return None   # anchor too close to the map edge for this orientation
        h1, h2 = nbrs[dirn % 6], nbrs[(dirn + 1) % 6]
        return [anchor, h1, h2]

    def do_drop(self, units3, hexes3):
        """Land a stick of three units on three mutually-adjacent hexes.
        Landing on a Web-occupied hex reveals it and triggers a Close
        Assault; landing on a cliff hex risks an avalanche (7.4.3)."""
        for u, h in zip(units3, hexes3):
            u.dropped_turn = self.turn
            if TERRAIN[h] == "cliff":
                if self.rng.randint(1, 6) == 6:
                    self.log.append(f"  Avalanche! {u.uid} destroyed dropping on {h}.")
                    u.alive = False
                    continue
            blocker = self.occupant_blocking(h, "UN")
            u.pos = h
            u.alive = True
            u.moved = False
            if blocker:
                blocker.face_up = True
                u.face_up = True
                self.close_assault(u, blocker)

    # -- reinforcements & dust ---------------------------------------------
    def do_web_reinforcements(self):
        edge_col = COLS if self.turn % 2 == 1 else 1
        pool = [u for u in self.units if u.side == "Web" and u.kind == "WI" and not u.alive][:4]
        for u in pool:
            for r in range(1, ROWS + 1):
                h = lab(edge_col, r)
                if self.unit_at(h) is None:
                    u.alive = True
                    u.pos = h
                    u.face_up = False
                    u.dusted = False
                    u.fired = False
                    u.moved = False
                    u.dropped_turn = None
                    self.log.append(f"  Web reinforcement: {u.uid} enters at {h}.")
                    break

    def dust_removal(self, side):
        for u in self.alive_units(side):
            u.dusted = False

    def reset_phase_flags(self, side):
        for u in self.alive_units(side):
            u.fired = False
            u.moved = False
            u.compelled_this_turn = getattr(u, "compelled_this_turn", False)

    # -- victory ------------------------------------------------------------
    def stacked_with_generator(self):
        return any(u.side == "UN" and u.alive and u.pos == self.gen.pos
                   for u in self.units)

    def check_stack_flag(self):
        if self.stacked_with_generator():
            self.ever_stacked = True

    def final_result(self):
        if self.stacked_with_generator():
            return "UN_WIN"
        if self.ever_stacked:
            return "DRAW"
        return "WEB_WIN"


def mutually_adjacent(a, b, c):
    return b in neighbors(a) and c in neighbors(a) and c in neighbors(b)


# ----------------------------------------------------------------------
# Web AI (the computer opponent)
# ----------------------------------------------------------------------

class WebAI:
    def setup(self, game):
        rng = game.rng
        zone_ok = [h for h in ZONE if TERRAIN[h] != "cliff"]
        gen_hex = rng.choice(zone_ok)
        game.gen.pos = gen_hex
        real_occupied = set()

        sp_candidates = [h for h in hexes_within(gen_hex, 2)
                          if TERRAIN[h] != "cliff" and h != gen_hex]
        rng.shuffle(sp_candidates)
        sps = [u for u in game.units if u.kind == "SP"]
        for sp in sps:
            for h in sp_candidates:
                if h not in real_occupied:
                    sp.pos = h
                    real_occupied.add(h)
                    break

        others = [u for u in game.units if u.kind in ("WI", "DUM")]
        radius = 4
        while True:
            pool = [h for h in hexes_within(gen_hex, radius)
                    if TERRAIN[h] != "cliff" and h not in real_occupied]
            if len(pool) >= len(others):
                break
            radius += 1
        rng.shuffle(pool)
        chosen = pool[:len(others)]
        rng.shuffle(others)
        for u, h in zip(others, chosen):
            u.pos = h
            if u.kind == "WI":
                real_occupied.add(h)

    def compulsion(self, game):
        candidates = [u for u in game.alive_units("UN") if u.pos]
        if not candidates:
            return
        target = min(candidates, key=lambda u: hex_dist(u.pos, game.gen.pos))
        reach = game.reachable(target, mf=3, ignore_terrain_stop=True)
        if not reach:
            return
        empty = {h: p for h, p in reach.items() if game.occupant_blocking(h, "UN") is None}
        pool = empty if empty else reach
        dest = max(pool.keys(), key=lambda h: hex_dist(h, game.gen.pos))
        if dest == target.pos:
            return
        game.log.append(f"Web compels {target.uid} ({target.pos} -> {dest})")
        game.move_unit(target, dest)
        target.compelled_this_turn = True

    def movement(self, game):
        for u in list(game.alive_units("Web")):
            if u.kind not in ("WI",) or not game.can_move_this_phase(u):
                continue
            targets = [t for t in game.alive_units("UN") if t.pos]
            if not targets:
                continue
            nearest = min(targets, key=lambda t: hex_dist(u.pos, t.pos))
            if hex_dist(u.pos, nearest.pos) <= u.rng:
                continue
            reach = game.reachable(u)
            if not reach:
                continue
            besth = min(reach.keys(),
                        key=lambda h: abs(hex_dist(h, nearest.pos) - u.rng))
            game.move_unit(u, besth)

    def ranged(self, game):
        used = set()
        for _ in range(30):
            best = None
            for t in game.alive_units("UN"):
                attackers = [a for a in game.alive_units("Web")
                             if a.uid not in used and a.cs > 0 and game.can_target(a, t)]
                if not attackers:
                    continue
                cs = sum(a.eff_cs(game) for a in attackers)
                col = odds_column(cs, t.eff_cs(game))
                rank = CRT_COLS.index(col)
                if best is None or rank > best[0]:
                    best = (rank, t, attackers)
            if not best:
                break
            _, t, attackers = best
            game.ranged_attack(attackers, t)
            used.update(a.uid for a in attackers)


# ----------------------------------------------------------------------
# A simple heuristic U.N. controller (used by --selftest; not needed for
# a human player, who is prompted interactively instead).
# ----------------------------------------------------------------------

class UNAuto:
    def initial_drops(self, game):
        reserve = [u for u in game.units if u.side == "UN" and u.pos is None]
        self._drop_all(game, reserve, "1521")

    def _drop_all(self, game, units, start):
        i = 0
        while i < len(units):
            stick = units[i:i + 3]
            placed = False
            for radius in range(0, 8):
                for anchor in hexes_within(start, radius):
                    for d in range(6):
                        tri = game.drop_triangle(anchor, d)
                        if not tri or len(set(tri)) != 3:
                            continue
                        if all(game.unit_at(h) is None for h in tri):
                            game.do_drop(stick, tri)
                            for u in stick:
                                u.setup_drop = True
                            placed = True
                            break
                    if placed:
                        break
                if placed:
                    break
            i += 3

    def drop_phase(self, game):
        pass   # this simple AI commits everything at setup

    def movement(self, game, second=False):
        for u in game.alive_units("UN"):
            if not u.pos or not game.can_move_this_phase(u):
                continue
            if second and u.kind != "LI":
                continue
            reach = game.reachable(u)
            if not reach:
                continue
            besth = min(reach.keys(), key=lambda h: hex_dist(h, ZONE_CENTER))
            if besth != u.pos:
                game.move_unit(u, besth)

    def ranged(self, game):
        used = set()
        for _ in range(30):
            best = None
            for t in game.alive_units("Web", real_only=True):
                attackers = [a for a in game.alive_units("UN")
                             if a.uid not in used and a.cs > 0 and game.can_target(a, t)]
                if not attackers:
                    continue
                cs = sum(a.eff_cs(game) for a in attackers)
                col = odds_column(cs, t.eff_cs(game))
                rank = CRT_COLS.index(col)
                if best is None or rank > best[0]:
                    best = (rank, t, attackers)
            if not best:
                break
            _, t, attackers = best
            game.ranged_attack(attackers, t)
            used.update(a.uid for a in attackers)


# ----------------------------------------------------------------------
# Text UI
# ----------------------------------------------------------------------

UN_GLYPH = {"HI": "HI", "LI": "LI", "LT": "LT"}
WEB_GLYPH = {"WI": "wi", "SP": "SP"}


def terrain_glyph(t):
    return {"clear": ".", "incline": "^", "cliff": "#"}[t]


def cell_str(game, h, reveal_all=False):
    real = [u for u in game.units_at(h) if u.real]
    if real:
        u = real[0]
        if u.side == "UN":
            return UN_GLYPH[u.kind]
        return WEB_GLYPH[u.kind] if (u.face_up or reveal_all) else "??"
    if any(u.kind == "DUM" for u in game.units_at(h)):
        return "dm" if reveal_all else "??"
    if reveal_all and any(u.kind == "GEN" for u in game.units_at(h)):
        return "GN"
    return " " + terrain_glyph(TERRAIN[h])


def print_map(game, reveal_all=False):
    print("     " + " ".join(f"{c:02d}" for c in range(1, COLS + 1)))
    for r in range(1, ROWS + 1):
        row = [cell_str(game, lab(c, r), reveal_all) for c in range(1, COLS + 1)]
        print(f"{r:02d}   " + " ".join(row))
    print("Legend: HI/LI/LT = your units   wi/SP = identified Web units   "
          "?? = unidentified Web counter")
    print("        .=clear  ^=incline(stops UN movement)  #=cliff(stops UN movement, "
          "avalanche risk)")


def print_status(game):
    print(f"\n-- Status: Game-Turn {game.turn} of 4, {game.turn_side} Player-Turn --")
    field = [u for u in game.units if u.side == "UN" and u.alive and u.pos]
    reserve = [u for u in game.units if u.side == "UN" and u.alive and u.pos is None]
    lost = [u for u in game.units if u.side == "UN" and not u.alive]
    print(f"U.N. forces: {len(field)} in the field, {len(reserve)} in reserve, {len(lost)} lost.")
    for u in sorted(field, key=lambda x: x.uid):
        tags = []
        if u.dusted:
            tags.append("DUSTED")
        if not game.can_move_this_phase(u):
            tags.append("can't move this phase")
        tag = f"  [{', '.join(tags)}]" if tags else ""
        print(f"  {u.uid:<4} {u.name:<22} CS{u.cs:>3} Rng{u.rng} MF{u.mf}  @ {u.pos}{tag}")
    if reserve:
        print("  Reserve: " + ", ".join(u.uid for u in reserve))
    known = [u for u in game.units if u.side == "Web" and u.alive and u.real and u.face_up]
    if known:
        print("Identified Web units:")
        for u in sorted(known, key=lambda x: x.uid):
            tag = "  [DUSTED]" if u.dusted else ""
            print(f"  {u.uid:<4} {u.name:<22} CS{u.cs:>3} Rng{u.rng}  @ {u.pos}{tag}")
    remaining_web_wi = len([u for u in game.units if u.side == "Web" and u.kind == "WI" and u.alive])
    print(f"Web Infantry remaining on/off board: {remaining_web_wi}   "
          f"Strongpoints remaining: {len([u for u in game.units if u.kind=='SP' and u.alive])}")
    if game.stacked_with_generator():
        print("*** A U.N. unit is standing on the Web Generator's hex right now! ***")


def show_new_log(game):
    for line in game.log[game._log_ptr:]:
        print(line)
    game._log_ptr = len(game.log)


def print_drop_help():
    print("  drop <u1> <h1> <u2> <h2> <u3> <h3>   land a reserve stick of 3 units on 3 mutually")
    print("                                        adjacent hexes, e.g.: drop HI1 1820 HI2 1821 HI3 1919")
    print("  reserve                               list units still in reserve")
    print("  map / status / done")


def print_move_help():
    print("  move <unit> <hex>   move a unit to a reachable hex (path found automatically).")
    print("                      Entering a hex with an enemy unit triggers a Close Assault")
    print("                      and ends that unit's move, even against a dummy.")
    print("  reach <unit>        list every hex that unit could move to this phase")
    print("  map / status / done")


def print_fire_help():
    print("  fire <unit>[,<unit>,...] <target>   combine one or more attackers on one target")
    print("  targets <unit>                      list valid targets in range for that unit")
    print("  map / status / done")


def human_drop_loop(game, mark_setup=False):
    while True:
        show_new_log(game)
        try:
            cmd = input("drop> ").strip()
        except EOFError:
            print()
            break
        if not cmd:
            continue
        parts = cmd.split()
        c = parts[0].lower()
        if c in ("done", "end"):
            break
        elif c == "help":
            print_drop_help()
        elif c == "map":
            print_map(game)
        elif c == "status":
            print_status(game)
        elif c == "reserve":
            r = [u.uid for u in game.units if u.side == "UN" and u.pos is None and u.alive]
            print("Reserve: " + (", ".join(r) if r else "(empty)"))
        elif c == "drop":
            if len(parts) != 7:
                print("Usage: drop <unit1> <hex1> <unit2> <hex2> <unit3> <hex3>")
                continue
            u1, h1, u2, h2, u3, h3 = parts[1:7]
            units = [game.find(u1), game.find(u2), game.find(u3)]
            hexes = [h1, h2, h3]
            if any(u is None for u in units):
                print("Unknown unit id."); continue
            if any(u.side != "UN" or u.pos is not None or not u.alive for u in units):
                print("All three units must be alive U.N. units currently in reserve."); continue
            if len(set(hexes)) != 3 or not all(h in ALL_HEXES for h in hexes):
                print("Need three distinct, valid hex labels."); continue
            if not mutually_adjacent(*hexes):
                print("The three hexes must be mutually adjacent (a triangle) -- rule 14.1."); continue
            game.do_drop(units, hexes)
            if mark_setup:
                for u in units:
                    u.setup_drop = True
            show_new_log(game)
        else:
            print("Unknown command. Type 'help'.")


def human_initial_drops(game):
    print("\n--- U.N. Initial Drops (before Game-Turn 1) ---")
    print("Drop as many of your 5 sticks of 3 as you like now; the rest stay in reserve")
    print("and can be dropped in later Drop Phases. 'help' for commands, 'done' to finish setup.")
    human_drop_loop(game, mark_setup=True)


def human_drop_phase(game):
    print("\n--- U.N. Drop Phase ---")
    reserve = [u for u in game.units if u.side == "UN" and u.pos is None and u.alive]
    if not reserve:
        print("(No units left in reserve.)")
        return
    human_drop_loop(game, mark_setup=False)


def human_movement_phase(game, second=False):
    label = "Second Movement Phase (Light Infantry only)" if second else "Movement Phase"
    print(f"\n--- U.N. {label} ---")
    eligible = [u for u in game.alive_units("UN") if u.pos and game.can_move_this_phase(u)
                and (u.kind == "LI" if second else True)]
    if not eligible:
        print("(No eligible units.)")
        return
    while True:
        show_new_log(game)
        try:
            cmd = input("move> ").strip()
        except EOFError:
            print()
            break
        if not cmd:
            continue
        parts = cmd.split()
        c = parts[0].lower()
        if c in ("done", "end"):
            break
        elif c == "help":
            print_move_help()
        elif c == "map":
            print_map(game)
        elif c == "status":
            print_status(game)
        elif c == "reach":
            if len(parts) < 2:
                print("Usage: reach <unit>"); continue
            u = game.find(parts[1])
            if not u or u.side != "UN" or u.pos is None or not u.alive:
                print("Invalid unit."); continue
            r = game.reachable(u)
            print(f"{u.uid} (MF {u.mf}) can reach: " +
                  (", ".join(sorted(r.keys())) if r else "(no legal moves)"))
        elif c == "move":
            if len(parts) < 3:
                print("Usage: move <unit> <dest_hex>"); continue
            u = game.find(parts[1])
            dest = parts[2]
            if not u or u.side != "UN" or u.pos is None or not u.alive:
                print("Invalid unit."); continue
            if second and u.kind != "LI":
                print("Only Light Infantry may move in the Second Movement Phase."); continue
            if not game.can_move_this_phase(u):
                print(f"{u.uid} may not move this phase (DUSTed / compelled / just dropped)."); continue
            r = game.reachable(u)
            if dest not in r:
                print("Not reachable this phase. Try 'reach %s'." % u.uid); continue
            game.move_unit(u, dest)
            show_new_log(game)
        else:
            print("Unknown command. Type 'help'.")


def human_ranged_phase(game):
    print("\n--- U.N. Ranged Combat Phase ---")
    while True:
        show_new_log(game)
        try:
            cmd = input("fire> ").strip()
        except EOFError:
            print()
            break
        if not cmd:
            continue
        parts = cmd.split()
        c = parts[0].lower()
        if c in ("done", "end"):
            break
        elif c == "help":
            print_fire_help()
        elif c == "map":
            print_map(game)
        elif c == "status":
            print_status(game)
        elif c == "targets":
            if len(parts) < 2:
                print("Usage: targets <unit>"); continue
            u = game.find(parts[1])
            if not u or u.side != "UN":
                print("Invalid unit."); continue
            ts = [f"{t.uid}@{t.pos}(CS{t.eff_cs(game)})" for t in game.alive_units("Web", real_only=True)
                  if game.can_target(u, t)]
            print("In range: " + (", ".join(ts) if ts else "(nothing in range)"))
        elif c == "fire":
            if len(parts) < 3:
                print("Usage: fire <unit>[,<unit>...] <target>"); continue
            attackers = [game.find(a) for a in parts[1].split(",")]
            target = game.find(parts[2])
            if any(a is None for a in attackers) or target is None:
                print("Unknown unit id(s)."); continue
            if any(a.side != "UN" or a.fired or not a.alive for a in attackers):
                print("All attackers must be alive U.N. units that haven't fired yet."); continue
            if not target.alive or not all(game.can_target(a, target) for a in attackers):
                print("Target is out of range (or invalid) for one or more attackers."); continue
            game.ranged_attack(attackers, target)
            show_new_log(game)
        else:
            print("Unknown command. Type 'help'.")


# ----------------------------------------------------------------------
# Turn sequence (6.0)
# ----------------------------------------------------------------------

def run_web_turn(game, ai):
    print(f"\n{'='*72}\n GAME-TURN {game.turn} of 4 -- WEB PLAYER-TURN\n{'='*72}")
    game.turn_side = "Web"
    for u in game.units:
        u.compelled_this_turn = False
    game.reset_phase_flags("Web")
    print("-- Compulsion Phase --")
    ai.compulsion(game)
    show_new_log(game)
    print("-- Reinforcement Phase --")
    game.do_web_reinforcements()
    show_new_log(game)
    print("-- Web Movement Phase --")
    ai.movement(game)
    show_new_log(game)
    game.check_stack_flag()
    print("-- Web Ranged Combat Phase --")
    ai.ranged(game)
    show_new_log(game)
    game.dust_removal("Web")


def run_un_turn(game, drop_fn, move_fn, ranged_fn):
    print(f"\n{'='*72}\n GAME-TURN {game.turn} of 4 -- U.N. PLAYER-TURN\n{'='*72}")
    game.turn_side = "UN"
    game.reset_phase_flags("UN")
    drop_fn(game)
    game.check_stack_flag()
    move_fn(game, second=False)
    game.check_stack_flag()
    ranged_fn(game)
    game.dust_removal("UN")
    move_fn(game, second=True)
    game.check_stack_flag()


def announce_result(game):
    result = game.final_result()
    print("\n" + "=" * 72)
    if result == "UN_WIN":
        print("U.N. VICTORY -- your raiders hold the Web Generator at the end of Game-Turn 4!")
    elif result == "DRAW":
        print("DRAW -- a U.N. unit reached the Web Generator during the raid, but was not")
        print("        holding it at the final bell.")
    else:
        print("WEB VICTORY -- no U.N. unit ever reached the Web Generator. The raid has failed.")
    print(f"(The Web Generator was hidden at hex {game.gen.pos}.)")
    print("=" * 72)
    return result


# ----------------------------------------------------------------------
# Self-test (automated Web-AI vs. simple U.N.-AI games, for regression
# testing -- no human input required)
# ----------------------------------------------------------------------

def run_selftest(n=20, seed=None):
    import traceback
    tally = {"UN_WIN": 0, "DRAW": 0, "WEB_WIN": 0}
    crashes = 0
    for i in range(n):
        try:
            game = Game(seed=(None if seed is None else seed + i))
            ai = WebAI()
            ai.setup(game)
            una = UNAuto()
            una.initial_drops(game)
            while game.turn <= 4:
                game.turn_side = "Web"
                for u in game.units:
                    u.compelled_this_turn = False
                game.reset_phase_flags("Web")
                ai.compulsion(game)
                game.do_web_reinforcements()
                ai.movement(game)
                game.check_stack_flag()
                ai.ranged(game)
                game.dust_removal("Web")
                game.turn_side = "UN"
                game.reset_phase_flags("UN")
                una.drop_phase(game)
                game.check_stack_flag()
                una.movement(game, second=False)
                game.check_stack_flag()
                una.ranged(game)
                game.dust_removal("UN")
                una.movement(game, second=True)
                game.check_stack_flag()
                game.turn += 1
            res = game.final_result()
            tally[res] += 1
        except Exception:
            crashes += 1
            print(f"Game {i}: CRASHED")
            traceback.print_exc()
    print(f"\nSelf-test: {n} games -> {tally}  ({crashes} crashed)")
    return crashes == 0


# ----------------------------------------------------------------------
# main
# ----------------------------------------------------------------------

BANNER = r"""
============================================================================
  OLYMPICA -- The U.N. Raid on Mars, 2206 A.D.   (Introductory Scenario)
  after the Metagaming MicroGame by Lynn Willis (1978)
============================================================================
You command the U.N. raiders (3 Laser Tanks, 9 Heavy Infantry, 3 Light
Infantry). The computer plays the Web, whose Generator, 2 Strongpoints,
10 Infantry and 3 dummy counters are hidden somewhere in the marked
"zone of uncertainty" near the map center -- you won't be told where.

WIN by having a U.N. unit stacked on the Generator's hex at the end of
Game-Turn 4. The game lasts 4 Game-Turns; each has a Web Player-Turn
(the computer moves/fires, and may compel one of your units) followed
by a U.N. Player-Turn (you drop, move, fire, then Light Infantry get a
second move). Hexes are labeled CCRR (column 01-26, row 01-23), e.g.
1413. Type 'help' at any prompt for that phase's commands.
============================================================================
"""


def play_interactive(seed=None):
    game = Game(seed=seed)
    ai = WebAI()
    print(BANNER)
    ai.setup(game)
    print("The Web forces have deployed, hidden, across the zone of uncertainty.")
    print_map(game)
    human_initial_drops(game)
    while game.turn <= 4:
        run_web_turn(game, ai)
        if not any(u.alive for u in game.alive_units("UN")):
            print("\nAll U.N. forces have been eliminated -- the raid has failed.")
            break
        run_un_turn(game, human_drop_phase, human_movement_phase, human_ranged_phase)
        game.turn += 1
    announce_result(game)


def main():
    import argparse
    p = argparse.ArgumentParser(
        description="OLYMPICA -- U.N. Raid on Mars, 2206 A.D. (Introductory Scenario)")
    p.add_argument("--seed", type=int, default=None, help="random seed, for reproducible games")
    p.add_argument("--selftest", type=int, nargs="?", const=20, default=None,
                    help="run N automated Web-AI vs. U.N.-AI games with no prompts, "
                         "for regression testing (default 20)")
    args = p.parse_args()
    if args.selftest is not None:
        ok = run_selftest(args.selftest, seed=args.seed)
        sys.exit(0 if ok else 1)
    try:
        play_interactive(seed=args.seed)
    except KeyboardInterrupt:
        print("\n(Raid aborted.)")


if __name__ == "__main__":
    main()
