#!/usr/bin/env python3
"""
OLYMPICA AI opponent / referee assistant
========================================

A self-contained Python opponent for the Web player in Lynn Willis's
OLYMPICA (Metagaming MicroGame 7, 1978).

The program is designed to sit beside the physical game.  It keeps the Web
player's face-down counters secret, chooses Web compulsion, reinforcement,
movement and ranged-combat actions, rolls/resolves combat, and stores the game
state in JSON.

Implemented closely enough for the four-turn Introductory Scenario:

* Axial four-digit map coordinates such as 1110 and 1210.
* Web hidden counters and dummies.
* Movement, stacking, no zones of control, ranged combat and the CRT.
* Close Assault's alternating 4-1 rolls.
* DUST, retreats, cliffs/inclines, avalanches and combat-strength modifiers.
* Web movement compulsion, drop compulsion and reinforcements.
* The special ranged-combat immunities of Laser Tanks and Strongpoints.
* Introductory victory conditions and permanent breaking of compulsion.

Advanced-scenario tunnels, Lifters, the BOAR drill, evacuation and the optional
Defensive Umbrellas/Demolition rules are deliberately not automated.  Their
unit definitions are present so states can be extended, but the AI is tuned for
the Introductory Scenario.

The supplied map is image-only, so the program does not pretend to contain a
perfect transcription of every map-edge and terrain hex.  By default it uses a
broad coordinate envelope and treats unspecified terrain as plain.  For a
physical game, add the cliff and incline hexes you need with the ``terrain``
command, or put an exact ``valid_hexes`` list in the JSON file.

Quick start
-----------

    python3 olympica_ai.py new olympica.json --seed 1978
    python3 olympica_ai.py show olympica.json

Place the U.N. initial drops (the Web may compel each three-unit drop):

    python3 olympica_ai.py drop olympica.json H1=1110,H2=1210,H3=1111
    python3 olympica_ai.py drop olympica.json T1=0910,L1=1010,L2=1011

Run the Web turn:

    python3 olympica_ai.py ai-turn olympica.json

Resolve a U.N. ranged attack, using either the program's die or a physical die:

    python3 olympica_ai.py un-attack olympica.json H1,H2 C07
    python3 olympica_ai.py un-attack olympica.json T1 C03 --die 4

Resolve a U.N. Close Assault:

    python3 olympica_ai.py un-assault olympica.json H1 C07

After finishing the U.N. turn:

    python3 olympica_ai.py end-un-turn olympica.json

Other useful commands:

    python3 olympica_ai.py place olympica.json H1 1312
    python3 olympica_ai.py eliminate olympica.json H1
    python3 olympica_ai.py dust olympica.json H1 on
    python3 olympica_ai.py terrain olympica.json cliff 0908 1009
    python3 olympica_ai.py terrain olympica.json incline 1717 1818
    python3 olympica_ai.py show olympica.json --omniscient
    python3 olympica_ai.py demo

The JSON file is intentionally human-readable.  Do not inspect it during a
face-to-face game unless you are happy to see the Web counters' identities.
"""

from __future__ import annotations

import argparse
import copy
import itertools
import json
import math
import os
import shutil
import sys
from dataclasses import asdict, dataclass, field
from enum import Enum
from pathlib import Path
from typing import Dict, Iterable, Iterator, List, Optional, Sequence, Set, Tuple


# ---------------------------------------------------------------------------
# Coordinates and map
# ---------------------------------------------------------------------------


@dataclass(frozen=True, order=True)
class Hex:
    """OLYMPICA's four-digit labels interpreted as axial hex coordinates.

    The map demonstrates the neighbour pattern around 0207:
    0206, 0208, 0107, 0108, 0306 and 0307.
    """

    q: int
    r: int

    @classmethod
    def parse(cls, text: str) -> "Hex":
        text = text.strip()
        if len(text) != 4 or not text.isdigit():
            raise ValueError(f"hex must be four digits, for example 1110: {text!r}")
        return cls(int(text[:2]), int(text[2:]))

    def label(self) -> str:
        if not (0 <= self.q <= 99 and 0 <= self.r <= 99):
            return f"({self.q},{self.r})"
        return f"{self.q:02d}{self.r:02d}"

    def neighbours(self) -> Tuple["Hex", ...]:
        return tuple(
            Hex(self.q + dq, self.r + dr)
            for dq, dr in ((-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0))
        )

    def distance(self, other: "Hex") -> int:
        dq = self.q - other.q
        dr = self.r - other.r
        return (abs(dq) + abs(dr) + abs(dq + dr)) // 2

    def add(self, delta: "Hex") -> "Hex":
        return Hex(self.q + delta.q, self.r + delta.r)

    def subtract(self, other: "Hex") -> "Hex":
        return Hex(self.q - other.q, self.r - other.r)


class Terrain(str, Enum):
    PLAIN = "plain"
    INCLINE = "incline"
    CLIFF = "cliff"


@dataclass
class Board:
    # The exact physical map may be supplied as valid_hexes.  Empty means use
    # the permissive envelope below.
    valid_hexes: Set[Hex] = field(default_factory=set)
    cliff: Set[Hex] = field(default_factory=set)
    incline: Set[Hex] = field(default_factory=set)
    q_min: int = 0
    q_max: int = 26
    r_min: int = 0
    r_max: int = 30

    def is_valid(self, h: Hex) -> bool:
        if self.valid_hexes:
            return h in self.valid_hexes
        return self.q_min <= h.q <= self.q_max and self.r_min <= h.r <= self.r_max

    def terrain(self, h: Hex) -> Terrain:
        if h in self.cliff:
            return Terrain.CLIFF
        if h in self.incline:
            return Terrain.INCLINE
        return Terrain.PLAIN

    def all_hexes(self) -> Iterable[Hex]:
        if self.valid_hexes:
            return sorted(self.valid_hexes)
        for q in range(self.q_min, self.q_max + 1):
            for r in range(self.r_min, self.r_max + 1):
                yield Hex(q, r)

    def to_dict(self) -> dict:
        return {
            "valid_hexes": sorted(h.label() for h in self.valid_hexes),
            "cliff": sorted(h.label() for h in self.cliff),
            "incline": sorted(h.label() for h in self.incline),
            "q_min": self.q_min,
            "q_max": self.q_max,
            "r_min": self.r_min,
            "r_max": self.r_max,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "Board":
        return cls(
            valid_hexes={Hex.parse(x) for x in data.get("valid_hexes", [])},
            cliff={Hex.parse(x) for x in data.get("cliff", [])},
            incline={Hex.parse(x) for x in data.get("incline", [])},
            q_min=int(data.get("q_min", 0)),
            q_max=int(data.get("q_max", 26)),
            r_min=int(data.get("r_min", 0)),
            r_max=int(data.get("r_max", 30)),
        )


# ---------------------------------------------------------------------------
# Units, state and scenarios
# ---------------------------------------------------------------------------


class Side(str, Enum):
    UN = "UN"
    WEB = "WEB"
    NEUTRAL = "NEUTRAL"

    def opponent(self) -> "Side":
        if self == Side.UN:
            return Side.WEB
        if self == Side.WEB:
            return Side.UN
        return Side.NEUTRAL


class UnitKind(str, Enum):
    UN_HEAVY = "UN heavy infantry"
    UN_LIGHT = "UN light infantry"
    LASER_TANK = "UN laser tank"
    LIFTER = "UN lifter"
    BOAR = "UN BOAR drill"
    WEB_INFANTRY = "Web infantry"
    STRONGPOINT = "Web strongpoint"
    DUMMY = "Web dummy"


@dataclass(frozen=True)
class UnitSpec:
    side: Side
    combat: int
    range: int
    movement: int
    parenthesised: bool = False
    can_ranged_attack: bool = True
    mobile: bool = True
    material_value: float = 1.0


SPECS: Dict[UnitKind, UnitSpec] = {
    UnitKind.UN_HEAVY: UnitSpec(Side.UN, 10, 2, 3, material_value=12),
    UnitKind.UN_LIGHT: UnitSpec(Side.UN, 6, 2, 3, material_value=9),
    UnitKind.LASER_TANK: UnitSpec(Side.UN, 25, 6, 2, material_value=36),
    UnitKind.LIFTER: UnitSpec(
        Side.UN, 10, 0, 25, parenthesised=True, can_ranged_attack=False, material_value=25
    ),
    UnitKind.BOAR: UnitSpec(
        Side.UN, 21, 0, 2, parenthesised=True, can_ranged_attack=False, material_value=24
    ),
    UnitKind.WEB_INFANTRY: UnitSpec(Side.WEB, 8, 2, 3, material_value=10),
    UnitKind.STRONGPOINT: UnitSpec(
        Side.WEB, 30, 7, 0, mobile=False, material_value=32
    ),
    UnitKind.DUMMY: UnitSpec(
        Side.WEB, 0, 0, 0, can_ranged_attack=False, mobile=False, material_value=0
    ),
}

INFANTRY_KINDS = {UnitKind.UN_HEAVY, UnitKind.UN_LIGHT, UnitKind.WEB_INFANTRY}


@dataclass
class Unit:
    id: str
    kind: UnitKind
    pos: Optional[Hex]
    eliminated: bool = False
    dust: bool = False
    revealed: bool = True
    dropped_this_turn: bool = False
    reinforced_this_turn: bool = False

    @property
    def spec(self) -> UnitSpec:
        return SPECS[self.kind]

    @property
    def side(self) -> Side:
        return self.spec.side

    @property
    def active(self) -> bool:
        return not self.eliminated and self.pos is not None

    @property
    def is_combat_unit(self) -> bool:
        return self.kind != UnitKind.DUMMY

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "kind": self.kind.value,
            "pos": self.pos.label() if self.pos else None,
            "eliminated": self.eliminated,
            "dust": self.dust,
            "revealed": self.revealed,
            "dropped_this_turn": self.dropped_this_turn,
            "reinforced_this_turn": self.reinforced_this_turn,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "Unit":
        return cls(
            id=str(data["id"]),
            kind=UnitKind(data["kind"]),
            pos=Hex.parse(data["pos"]) if data.get("pos") else None,
            eliminated=bool(data.get("eliminated", False)),
            dust=bool(data.get("dust", False)),
            revealed=bool(data.get("revealed", True)),
            dropped_this_turn=bool(data.get("dropped_this_turn", False)),
            reinforced_this_turn=bool(data.get("reinforced_this_turn", False)),
        )


@dataclass
class GameState:
    scenario: str
    turn: int
    max_turns: int
    generator: Hex
    board: Board
    units: Dict[str, Unit]
    compulsion_broken: bool = False
    rng: int = 1978
    history: List[str] = field(default_factory=list)

    def log(self, message: str) -> None:
        self.history.append(message)
        if len(self.history) > 400:
            self.history = self.history[-400:]
        print(message)

    def roll_d6(self, forced: Optional[int] = None) -> int:
        if forced is not None:
            if forced < 1 or forced > 6:
                raise ValueError("die roll must be 1..6")
            return forced
        # Small deterministic LCG so a saved game continues reproducibly.
        self.rng = (1664525 * self.rng + 1013904223) & 0xFFFFFFFF
        return ((self.rng >> 16) % 6) + 1

    def unit(self, unit_id: str) -> Unit:
        try:
            return self.units[unit_id.upper()]
        except KeyError as exc:
            raise ValueError(f"unknown unit {unit_id!r}") from exc

    def active_units(self, side: Optional[Side] = None) -> List[Unit]:
        result = [u for u in self.units.values() if u.active]
        if side is not None:
            result = [u for u in result if u.side == side]
        return result

    def units_at(self, h: Hex, side: Optional[Side] = None) -> List[Unit]:
        result = [u for u in self.active_units(side) if u.pos == h]
        return sorted(result, key=lambda u: u.id)

    def blocking_unit_at(self, h: Hex, side: Optional[Side] = None) -> Optional[Unit]:
        # Dummies do not count for stacking.
        for u in self.units_at(h, side):
            if u.kind != UnitKind.DUMMY:
                return u
        return None

    def enemy_units_at(self, h: Hex, side: Side) -> List[Unit]:
        return self.units_at(h, side.opponent())

    def un_on_generator(self) -> bool:
        return any(u.pos == self.generator for u in self.active_units(Side.UN))

    def update_compulsion_status(self) -> None:
        if self.un_on_generator() and not self.compulsion_broken:
            self.compulsion_broken = True
            self.log("The Web of Compulsion is permanently broken: a U.N. unit reached the Generator.")

    def to_dict(self) -> dict:
        return {
            "format": "olympica-ai-state-v1",
            "scenario": self.scenario,
            "turn": self.turn,
            "max_turns": self.max_turns,
            "generator": self.generator.label(),
            "board": self.board.to_dict(),
            "units": {uid: u.to_dict() for uid, u in sorted(self.units.items())},
            "compulsion_broken": self.compulsion_broken,
            "rng": self.rng,
            "history": self.history,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "GameState":
        if data.get("format") not in (None, "olympica-ai-state-v1"):
            raise ValueError(f"unsupported state format: {data.get('format')}")
        units = {uid.upper(): Unit.from_dict(raw) for uid, raw in data["units"].items()}
        return cls(
            scenario=str(data.get("scenario", "introductory")),
            turn=int(data.get("turn", 1)),
            max_turns=int(data.get("max_turns", 4)),
            generator=Hex.parse(data["generator"]),
            board=Board.from_dict(data.get("board", {})),
            units=units,
            compulsion_broken=bool(data.get("compulsion_broken", False)),
            rng=int(data.get("rng", 1978)),
            history=list(data.get("history", [])),
        )


WEB_SETUP_OFFSETS: Dict[UnitKind, List[Tuple[int, int]]] = {
    UnitKind.STRONGPOINT: [(-1, 0), (1, 0)],
    UnitKind.WEB_INFANTRY: [
        (0, -1),
        (0, 1),
        (1, -1),
        (-1, 1),
        (2, -1),
        (1, 1),
        (0, 2),
        (-1, 2),
        (-2, 1),
        (-2, 0),
    ],
    UnitKind.DUMMY: [(1, -2), (2, -2), (2, 0)],
}


def create_intro_state(generator: Hex, seed: int) -> GameState:
    board = Board()
    state = GameState(
        scenario="introductory",
        turn=1,
        max_turns=4,
        generator=generator,
        board=board,
        units={},
        rng=seed & 0xFFFFFFFF,
    )

    # Build the actual Web identities/positions, then assign neutral public IDs
    # C01..C15.  The public number gives the U.N. player no information.
    secret_counters: List[Tuple[UnitKind, Hex]] = []
    for kind, offsets in WEB_SETUP_OFFSETS.items():
        for dq, dr in offsets:
            p = Hex(generator.q + dq, generator.r + dr)
            if not board.is_valid(p):
                raise ValueError(f"default setup leaves the map at {p.label()}; choose another generator")
            secret_counters.append((kind, p))

    # Shuffle public labels without changing the tactically sensible setup.
    labels = [f"C{i:02d}" for i in range(1, len(secret_counters) + 1)]
    for i in range(len(labels) - 1, 0, -1):
        j = state.roll_d6() % (i + 1)
        labels[i], labels[j] = labels[j], labels[i]

    for label, (kind, pos) in zip(labels, secret_counters):
        state.units[label] = Unit(label, kind, pos, revealed=False)

    for i in range(1, 10):
        uid = f"H{i}"
        state.units[uid] = Unit(uid, UnitKind.UN_HEAVY, None, revealed=True)
    for i in range(1, 4):
        uid = f"L{i}"
        state.units[uid] = Unit(uid, UnitKind.UN_LIGHT, None, revealed=True)
    for i in range(1, 4):
        uid = f"T{i}"
        state.units[uid] = Unit(uid, UnitKind.LASER_TANK, None, revealed=True)

    state.history.append(
        f"Introductory game created. Generator at {generator.label()}; Web counters deployed face-down."
    )
    return state


# ---------------------------------------------------------------------------
# Persistence and display
# ---------------------------------------------------------------------------


def load_state(path: Path) -> GameState:
    try:
        with path.open("r", encoding="utf-8") as f:
            return GameState.from_dict(json.load(f))
    except FileNotFoundError as exc:
        raise SystemExit(f"state file does not exist: {path}") from exc
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        raise SystemExit(f"cannot load {path}: {exc}") from exc


def save_state(state: GameState, path: Path, make_backup: bool = True) -> None:
    try:
        if make_backup and path.exists():
            shutil.copy2(path, path.with_suffix(path.suffix + ".bak"))
        temp = path.with_suffix(path.suffix + ".tmp")
        with temp.open("w", encoding="utf-8") as f:
            json.dump(state.to_dict(), f, indent=2, sort_keys=True)
            f.write("\n")
        os.replace(temp, path)
    except OSError as exc:
        raise SystemExit(f"cannot save {path}: {exc}") from exc


def display_state(state: GameState, omniscient: bool = False) -> None:
    print(f"OLYMPICA - {state.scenario} scenario - Game-Turn {state.turn}/{state.max_turns}")
    print(f"Web Generator: {state.generator.label()}")
    print(f"Web of Compulsion: {'BROKEN' if state.compulsion_broken else 'active'}")
    print()

    print("U.N. forces")
    for u in sorted((x for x in state.units.values() if x.side == Side.UN), key=lambda x: x.id):
        status = "eliminated" if u.eliminated else (u.pos.label() if u.pos else "off map")
        flags = []
        if u.dust:
            flags.append("DUST")
        if u.dropped_this_turn:
            flags.append("dropped this turn")
        suffix = f" [{' / '.join(flags)}]" if flags else ""
        print(f"  {u.id:>3}  {u.kind.value:<22} {status}{suffix}")

    print("\nWeb counters")
    for u in sorted((x for x in state.units.values() if x.side == Side.WEB), key=lambda x: x.id):
        status = "eliminated" if u.eliminated else (u.pos.label() if u.pos else "off map")
        identity = u.kind.value if (omniscient or u.revealed or u.eliminated) else "FACE-DOWN"
        flags = []
        if u.dust:
            flags.append("DUST")
        if u.reinforced_this_turn:
            flags.append("reinforcement")
        suffix = f" [{' / '.join(flags)}]" if flags else ""
        print(f"  {u.id:>3}  {identity:<22} {status}{suffix}")

    print("\nRecent record")
    if not state.history:
        print("  (none)")
    else:
        for line in state.history[-12:]:
            print(f"  {line}")
    print()
    print(victory_status(state))


# ---------------------------------------------------------------------------
# Core rules
# ---------------------------------------------------------------------------


CRT: Dict[str, Tuple[str, ...]] = {
    "1-3": ("AE", "AE", "AE", "AE", "AR2", "DUST"),
    "1-2": ("AE", "AE", "EX", "AR2", "DUST", "DR2"),
    "1-1": ("EX", "AR2", "DUST", "DUST", "DR2", "EX"),
    "2-1": ("AR2", "DUST", "DUST", "DR2", "EX", "DE"),
    "3-1": ("DUST", "DUST", "DR2", "EX", "DE", "DE"),
    "4-1": ("DUST", "DR2", "EX", "DE", "DE", "DE"),
}


def odds_column(attack: int, defence: int) -> str:
    if defence <= 0:
        return "4-1"
    ratio = attack / defence
    # Round in the defender's favour.
    if ratio < 0.5:
        return "1-3"
    if ratio < 1.0:
        return "1-2"
    if ratio < 2.0:
        return "1-1"
    if ratio < 3.0:
        return "2-1"
    if ratio < 4.0:
        return "3-1"
    return "4-1"


def effective_combat_strength(state: GameState, unit: Unit) -> int:
    cs = unit.spec.combat
    if unit.dust:
        cs = math.ceil(cs / 2)
    if unit.pos is not None and state.board.terrain(unit.pos) == Terrain.CLIFF:
        cs = math.ceil(cs / 2)
    return cs


def printed_combat_strength(unit: Unit) -> int:
    return unit.spec.combat


def ranged_distance(attacker: Unit, defender: Unit) -> int:
    assert attacker.pos is not None and defender.pos is not None
    return attacker.pos.distance(defender.pos)


def can_ranged_attack(state: GameState, attacker: Unit, defender: Unit) -> bool:
    if not attacker.active or not defender.active:
        return False
    if attacker.side == defender.side:
        return False
    if not attacker.spec.can_ranged_attack or attacker.spec.range <= 0:
        return False
    if attacker.pos is None or defender.pos is None:
        return False
    return attacker.pos.distance(defender.pos) <= attacker.spec.range


def reveal(state: GameState, unit: Unit, reason: str) -> None:
    if unit.side == Side.WEB and not unit.revealed:
        unit.revealed = True
        state.log(f"{unit.id} is revealed as {unit.kind.value} ({reason}).")


def eliminate(state: GameState, unit: Unit, reason: str) -> None:
    if unit.eliminated:
        return
    reveal(state, unit, "eliminated")
    old = unit.pos.label() if unit.pos else "off map"
    unit.eliminated = True
    unit.pos = None
    unit.dust = False
    unit.dropped_this_turn = False
    unit.reinforced_this_turn = False
    state.log(f"{unit.id} ({unit.kind.value}) is eliminated from {old}: {reason}.")


def attacker_immune_to_adverse_result(
    attacker: Unit,
    defender: Unit,
    result: str,
    distance: int,
) -> bool:
    # Units attacking a parenthesised-strength defender do not suffer AE/EX.
    if defender.spec.parenthesised and result in {"AE", "EX"}:
        return True

    # Laser Tanks and Strongpoints attacking infantry ignore AE, AR2 and EX.
    if (
        attacker.kind in {UnitKind.LASER_TANK, UnitKind.STRONGPOINT}
        and defender.kind in INFANTRY_KINDS
        and result in {"AE", "AR2", "EX"}
    ):
        return True

    # Strongpoints cannot retreat, and ignore AE/EX when firing at range seven.
    if attacker.kind == UnitKind.STRONGPOINT:
        if result == "AR2":
            return True
        if distance == 7 and result in {"AE", "EX"}:
            return True

    return False


def defender_ignores_result(defender: Unit, result: str) -> bool:
    if defender.kind == UnitKind.STRONGPOINT and result in {"DR2", "DUST"}:
        return True
    return False


def occupied_friendly(state: GameState, h: Hex, side: Side, exclude: Optional[str] = None) -> bool:
    for u in state.units_at(h, side):
        if u.id != exclude and u.kind != UnitKind.DUMMY:
            return True
    return False


def shortest_paths_within(
    state: GameState,
    start: Hex,
    max_steps: int,
    moving_side: Side,
    allow_enemy_destination: bool = True,
) -> Dict[Hex, List[Hex]]:
    """Reachability for ordinary movement.

    Friendly combat units may be crossed but not occupied at the end.  Enemy
    units stop movement and can only be destinations for Close Assault.
    """

    paths: Dict[Hex, List[Hex]] = {start: [start]}
    frontier = [start]
    while frontier:
        cur = frontier.pop(0)
        steps = len(paths[cur]) - 1
        if steps >= max_steps:
            continue
        for nxt in cur.neighbours():
            if not state.board.is_valid(nxt) or nxt in paths:
                continue
            enemy_here = state.blocking_unit_at(nxt, moving_side.opponent())
            paths[nxt] = paths[cur] + [nxt]
            if enemy_here is None:
                frontier.append(nxt)
            elif not allow_enemy_destination:
                del paths[nxt]
    return paths


def hex_ring(state: GameState, centre: Hex, radius: int) -> List[Hex]:
    return [h for h in state.board.all_hexes() if centre.distance(h) == radius]


def choose_retreat_destination(
    state: GameState,
    unit: Unit,
    chooser: Side,
    origin: Hex,
) -> Optional[Hex]:
    candidates: List[Hex] = []
    enemy_occupied: List[Hex] = []
    for h in hex_ring(state, origin, 2):
        if occupied_friendly(state, h, unit.side, exclude=unit.id):
            continue
        if state.blocking_unit_at(h, unit.side.opponent()):
            enemy_occupied.append(h)
        else:
            candidates.append(h)

    if not candidates:
        candidates = enemy_occupied
    if not candidates:
        return None

    def score(h: Hex) -> float:
        old = unit.pos
        unit.pos = h
        value = evaluate_state(state)
        unit.pos = old
        # The Web chooser maximises; the U.N. chooser minimises Web's score.
        return value if chooser == Side.WEB else -value

    return max(candidates, key=lambda h: (score(h), h.label()))


def retreat_unit(
    state: GameState,
    unit: Unit,
    chooser: Side,
    origin: Hex,
    reason: str,
) -> bool:
    if unit.kind == UnitKind.STRONGPOINT:
        state.log(f"{unit.id} is a Strongpoint and ignores the retreat result.")
        return False
    destination = choose_retreat_destination(state, unit, chooser, origin)
    if destination is None:
        state.log(f"{unit.id} has no legal two-hex retreat and remains at {origin.label()}.")
        return False

    unit.pos = destination
    state.log(f"{unit.id} retreats from {origin.label()} to {destination.label()} ({reason}).")

    if unit.side == Side.UN and state.board.terrain(destination) == Terrain.CLIFF:
        if unit.kind in {UnitKind.LIFTER, UnitKind.BOAR}:
            eliminate(state, unit, "retreated into cliff terrain")
        else:
            die = state.roll_d6()
            state.log(f"Avalanche check for {unit.id}: rolled {die}.")
            if die == 6:
                eliminate(state, unit, "avalanche during retreat")
    if unit.side == Side.UN and state.board.terrain(destination) == Terrain.INCLINE:
        if unit.kind in {UnitKind.LIFTER, UnitKind.BOAR}:
            eliminate(state, unit, "retreated into incline terrain")

    # A retreat onto an enemy is only used if no ordinary destination exists.
    enemy = state.blocking_unit_at(destination, unit.side.opponent())
    if unit.active and enemy:
        state.log(f"Retreat into an enemy at {destination.label()} causes a Close Assault.")
        resolve_close_assault(state, unit, enemy)
    state.update_compulsion_status()
    return True


def choose_exchange_losses(attackers: Sequence[Unit], required_cs: int) -> List[Unit]:
    if not attackers:
        return []
    best: Optional[Tuple[float, int, Tuple[str, ...], Tuple[Unit, ...]]] = None
    for n in range(1, len(attackers) + 1):
        for combo in itertools.combinations(attackers, n):
            strength = sum(printed_combat_strength(u) for u in combo)
            if strength < required_cs:
                continue
            value = sum(u.spec.material_value for u in combo)
            key = (value, strength, tuple(sorted(u.id for u in combo)), combo)
            if best is None or key[:3] < best[:3]:
                best = key
    if best is None:
        return list(attackers)
    return list(best[3])


def resolve_ranged_attack(
    state: GameState,
    attacker_ids: Sequence[str],
    defender_id: str,
    forced_die: Optional[int] = None,
) -> str:
    attackers = [state.unit(uid) for uid in attacker_ids]
    defender = state.unit(defender_id)
    if not attackers:
        raise ValueError("at least one attacker is required")
    if not defender.active:
        raise ValueError(f"defender {defender.id} is not on the map")
    if len({u.side for u in attackers}) != 1:
        raise ValueError("all attackers must belong to the same side")
    if any(not can_ranged_attack(state, u, defender) for u in attackers):
        bad = [u.id for u in attackers if not can_ranged_attack(state, u, defender)]
        raise ValueError(f"not legal ranged attackers against {defender.id}: {', '.join(bad)}")
    if any(u.id == defender.id for u in attackers):
        raise ValueError("a unit cannot attack itself")

    reveal(state, defender, "attacked by ranged combat")
    for u in attackers:
        reveal(state, u, "fired")

    if defender.kind == UnitKind.DUMMY:
        eliminate(state, defender, "dummy attacked by ranged combat")
        return "DUMMY"

    attack_cs = sum(effective_combat_strength(state, u) for u in attackers)
    defence_cs = effective_combat_strength(state, defender)
    column = odds_column(attack_cs, defence_cs)
    die = state.roll_d6(forced_die)
    result = CRT[column][die - 1]
    state.log(
        f"Ranged attack {','.join(u.id for u in attackers)} -> {defender.id}: "
        f"{attack_cs}:{defence_cs}, column {column}, die {die}, result {result}."
    )

    distances = {u.id: ranged_distance(u, defender) for u in attackers}
    vulnerable = [
        u
        for u in attackers
        if not attacker_immune_to_adverse_result(u, defender, result, distances[u.id])
    ]

    if result == "AE":
        if not vulnerable:
            state.log("All attackers ignore AE in this attack.")
        for u in vulnerable:
            eliminate(state, u, "AE - attacker eliminated")

    elif result == "DE":
        eliminate(state, defender, "DE - defender eliminated")

    elif result == "AR2":
        if not vulnerable:
            state.log("All attackers ignore AR2 in this attack.")
        for u in list(vulnerable):
            if u.active and u.pos is not None:
                retreat_unit(state, u, defender.side, u.pos, "AR2")

    elif result == "DR2":
        if defender_ignores_result(defender, result):
            state.log(f"{defender.id} ignores DR2.")
        elif defender.pos is not None:
            retreat_unit(state, defender, attackers[0].side, defender.pos, "DR2")

    elif result == "DUST":
        if defender_ignores_result(defender, result):
            state.log(f"{defender.id} ignores DUST.")
        else:
            defender.dust = True
            state.log(f"DUST marker placed on {defender.id}; it cannot move next phase and its CS is halved.")

    elif result == "EX":
        eliminate(state, defender, "EX - exchange")
        losses = choose_exchange_losses(vulnerable, printed_combat_strength(defender))
        if not losses and vulnerable:
            losses = list(vulnerable)
        if not losses:
            state.log("The attackers are immune to the adverse part of EX.")
        for u in losses:
            eliminate(state, u, "EX - exchange loss")

    state.update_compulsion_status()
    return result


def close_assault_outcome_values() -> Dict[str, float]:
    """Absorption probabilities when an ordinary defender rolls first.

    Used only as an AI heuristic.  Actual Close Assaults roll normally.
    """

    prob_d_turn = 1.0
    prob_a_turn = 0.0
    outcomes = {
        "attacker_retreat": 0.0,
        "defender_retreat": 0.0,
        "attacker_eliminated": 0.0,
        "defender_eliminated": 0.0,
        "both_eliminated": 0.0,
    }
    for _ in range(100):
        if prob_d_turn + prob_a_turn < 1e-12:
            break
        nd = 0.0
        na = 0.0
        if prob_d_turn:
            outcomes["attacker_retreat"] += prob_d_turn / 6
            outcomes["both_eliminated"] += prob_d_turn / 6
            outcomes["attacker_eliminated"] += prob_d_turn * 3 / 6
            na += prob_d_turn / 6  # DUST is ignored; pass the die.
        if prob_a_turn:
            outcomes["defender_retreat"] += prob_a_turn / 6
            outcomes["both_eliminated"] += prob_a_turn / 6
            outcomes["defender_eliminated"] += prob_a_turn * 3 / 6
            nd += prob_a_turn / 6
        prob_d_turn, prob_a_turn = nd, na
    return outcomes


CA_PROBS = close_assault_outcome_values()


def resolve_close_assault(
    state: GameState,
    attacker: Unit,
    defender: Unit,
    forced_dice: Optional[Sequence[int]] = None,
) -> str:
    if not attacker.active or not defender.active:
        raise ValueError("both Close Assault units must be active")
    if attacker.side == defender.side:
        raise ValueError("Close Assault requires opposing units")
    if defender.pos is None or attacker.pos is None:
        raise ValueError("both units must be on the map")

    assault_hex = defender.pos
    attacker_origin = attacker.pos
    attacker.pos = assault_hex
    reveal(state, attacker, "entered Close Assault")
    reveal(state, defender, "Close Assaulted")
    state.log(f"Close Assault: {attacker.id} enters {assault_hex.label()} against {defender.id}.")

    if defender.kind == UnitKind.DUMMY:
        eliminate(state, defender, "dummy Close Assaulted")
        state.update_compulsion_status()
        return "DUMMY"

    dice_iter = iter(forced_dice or [])
    roller = defender
    target = attacker
    for exchange_no in range(1, 101):
        try:
            forced = next(dice_iter)
        except StopIteration:
            forced = None
        die = state.roll_d6(forced)
        result = CRT["4-1"][die - 1]
        state.log(f"  {roller.id} rolls {die} on 4-1 against {target.id}: {result}.")

        if result == "DUST":
            state.log("  DUST is ignored in Close Assault; the die passes.")
        elif result == "DR2":
            if target.kind == UnitKind.STRONGPOINT:
                state.log(f"  {target.id} ignores the retreat result; the die passes.")
            else:
                origin = assault_hex
                retreat_unit(state, target, roller.side, origin, "Close Assault DR2")
                state.update_compulsion_status()
                return "RETREAT"
        elif result == "EX":
            eliminate(state, attacker, "Close Assault EX")
            eliminate(state, defender, "Close Assault EX")
            state.update_compulsion_status()
            return "EX"
        elif result == "DE":
            eliminate(state, target, "Close Assault DE")
            survivor = roller
            if survivor.active:
                survivor.pos = assault_hex
            state.update_compulsion_status()
            return "DE"

        roller, target = target, roller

    # This is practically unreachable; it protects against a pathological
    # forced-dice stream of only ones/twos against an immobile Strongpoint.
    state.log("Close Assault stopped after 100 exchanges; positions restored conservatively.")
    if attacker.active:
        attacker.pos = attacker_origin
    return "NO_RESULT"


def apply_un_terrain_entry(state: GameState, unit: Unit, destination: Hex, context: str) -> bool:
    terrain = state.board.terrain(destination)
    if terrain == Terrain.PLAIN:
        return True
    if unit.kind in {UnitKind.LIFTER, UnitKind.BOAR}:
        eliminate(state, unit, f"entered {terrain.value} terrain during {context}")
        return False
    if terrain == Terrain.CLIFF:
        die = state.roll_d6()
        state.log(f"Avalanche check for {unit.id} entering {destination.label()}: rolled {die}.")
        if die == 6:
            eliminate(state, unit, f"avalanche during {context}")
            return False
    return True


# ---------------------------------------------------------------------------
# AI evaluation and action selection
# ---------------------------------------------------------------------------


def evaluate_state(state: GameState) -> float:
    """Heuristic from the Web player's point of view."""

    score = 0.0
    for u in state.units.values():
        if not u.active:
            continue
        value = u.spec.material_value
        if u.dust:
            value *= 0.82
        score += value if u.side == Side.WEB else -value

    un_units = state.active_units(Side.UN)
    web_units = state.active_units(Side.WEB)

    if state.un_on_generator():
        score -= 10000.0
    elif un_units:
        nearest = min(u.pos.distance(state.generator) for u in un_units if u.pos is not None)
        score -= max(0, 8 - nearest) * 70
        for u in un_units:
            assert u.pos is not None
            d = u.pos.distance(state.generator)
            if d <= 2:
                score -= (3 - d) * (50 + u.spec.material_value)

    for u in web_units:
        assert u.pos is not None
        d = u.pos.distance(state.generator)
        if u.kind == UnitKind.STRONGPOINT:
            score += max(0, 4 - d) * 12
        elif u.kind == UnitKind.WEB_INFANTRY:
            score += max(0, 4 - d) * 4

    # Reward current firing opportunities and discourage easy U.N. shots.
    for w in web_units:
        if w.spec.can_ranged_attack:
            for un in un_units:
                if can_ranged_attack(state, w, un):
                    score += 1.2 + un.spec.material_value * 0.08
    for un in un_units:
        if un.spec.can_ranged_attack:
            for w in web_units:
                if can_ranged_attack(state, un, w):
                    score -= 0.5 + w.spec.material_value * 0.04

    return score


def local_web_position_score(state: GameState, unit: Unit, destination: Hex) -> float:
    assert unit.side == Side.WEB
    old = unit.pos
    unit.pos = destination
    score = evaluate_state(state)

    # Tactical terms stronger than the global evaluator for one-unit movement.
    for enemy in state.active_units(Side.UN):
        assert enemy.pos is not None
        d = destination.distance(enemy.pos)
        if d <= unit.spec.range:
            score += enemy.spec.material_value * 0.8
        if enemy.kind == UnitKind.LASER_TANK and d <= enemy.spec.range:
            score -= 6
        if d == 1:
            score += 2  # threat of a Close Assault next turn

    # Hidden Web counters have genuine informational value.  Moving exposes a
    # counter, so demand a modest tactical improvement before breaking cover.
    if not unit.revealed and old is not None and destination != old:
        score -= 7.5

    # A screen one or two hexes from the generator is generally useful.
    dg = destination.distance(state.generator)
    if dg in (1, 2):
        score += 12
    elif dg > 4:
        score -= (dg - 4) * 4

    unit.pos = old
    return score


def close_assault_heuristic(attacker: Unit, defender: Unit) -> float:
    p_target_removed = CA_PROBS["defender_eliminated"] + CA_PROBS["both_eliminated"]
    p_attacker_removed = CA_PROBS["attacker_eliminated"] + CA_PROBS["both_eliminated"]
    p_target_retreat = CA_PROBS["defender_retreat"]
    p_attacker_retreat = CA_PROBS["attacker_retreat"]
    return (
        defender.spec.material_value * (p_target_removed + 0.3 * p_target_retreat)
        - attacker.spec.material_value * (p_attacker_removed + 0.15 * p_attacker_retreat)
    )


def web_compulsion_phase(state: GameState) -> None:
    state.update_compulsion_status()
    if state.compulsion_broken:
        state.log("Web Compulsion Phase: skipped; compulsion has been broken.")
        return

    candidates: List[Tuple[float, Unit, Hex, List[Hex]]] = []
    for unit in state.active_units(Side.UN):
        if unit.kind == UnitKind.BOAR:
            continue
        assert unit.pos is not None
        paths = shortest_paths_within(state, unit.pos, 3, Side.UN, allow_enemy_destination=False)
        for dest, path in paths.items():
            if dest == unit.pos:
                continue
            if occupied_friendly(state, dest, Side.UN, exclude=unit.id):
                continue
            old = unit.pos
            before_d = old.distance(state.generator)
            unit.pos = dest
            after_d = dest.distance(state.generator)
            score = evaluate_state(state) + (after_d - before_d) * 45
            unit.pos = old
            if state.board.terrain(dest) == Terrain.CLIFF:
                score += unit.spec.material_value * 0.22
            candidates.append((score, unit, dest, path))

    if not candidates:
        state.log("Web Compulsion Phase: no legal U.N. move.")
        return

    _, unit, dest, path = max(candidates, key=lambda x: (x[0], x[2].label(), x[1].id))
    origin = unit.pos
    assert origin is not None
    unit.pos = dest
    state.log(
        f"Web Compulsion Phase: {unit.id} is compelled {origin.label()} -> {dest.label()} "
        f"({len(path) - 1} hexes)."
    )
    apply_un_terrain_entry(state, unit, dest, "movement compulsion")
    state.update_compulsion_status()


def board_edge_hexes(state: GameState, east: bool) -> List[Hex]:
    valid = list(state.board.all_hexes())
    if not valid:
        return []
    edge_q = max(h.q for h in valid) if east else min(h.q for h in valid)
    return [h for h in valid if h.q == edge_q]


def web_reinforcement_phase(state: GameState) -> None:
    eliminated = [
        u for u in state.units.values() if u.kind == UnitKind.WEB_INFANTRY and u.eliminated
    ]
    if not eliminated:
        state.log("Web Reinforcement Phase: no eliminated Web infantry are available.")
        return

    east = state.turn % 2 == 1
    edge_name = "east" if east else "west"
    entries = [
        h
        for h in board_edge_hexes(state, east)
        if not occupied_friendly(state, h, Side.WEB)
        and state.blocking_unit_at(h, Side.UN) is None
    ]
    if not entries:
        state.log(f"Web Reinforcement Phase: no open {edge_name}-edge entry hex.")
        return

    count = min(4, len(eliminated), len(entries))
    # Prefer entries closest to the generator and then to a U.N. target.
    un_units = state.active_units(Side.UN)

    def entry_score(h: Hex) -> Tuple[int, int, str]:
        nearest_un = min((h.distance(u.pos) for u in un_units if u.pos), default=99)
        return (h.distance(state.generator), nearest_un, h.label())

    entries.sort(key=entry_score)
    for unit, h in zip(sorted(eliminated, key=lambda u: u.id)[:count], entries[:count]):
        unit.eliminated = False
        unit.pos = h
        unit.dust = False
        unit.revealed = True  # Reinforcements enter openly.
        unit.reinforced_this_turn = True
        state.log(f"Web reinforcement {unit.id} enters from the {edge_name} edge at {h.label()}.")


def web_movement_phase(state: GameState) -> None:
    movers = [
        u
        for u in state.active_units(Side.WEB)
        if u.kind == UnitKind.WEB_INFANTRY and not u.dust
    ]

    # Units nearer the action choose first.
    def urgency(u: Unit) -> Tuple[int, int, str]:
        assert u.pos is not None
        un_dist = min(
            (u.pos.distance(e.pos) for e in state.active_units(Side.UN) if e.pos),
            default=99,
        )
        return (un_dist, u.pos.distance(state.generator), u.id)

    for unit in sorted(movers, key=urgency):
        if not unit.active or unit.pos is None:
            continue
        allowance = unit.spec.movement - (1 if unit.reinforced_this_turn else 0)
        if allowance <= 0:
            continue
        paths = shortest_paths_within(state, unit.pos, allowance, Side.WEB, allow_enemy_destination=True)

        best_ca: Optional[Tuple[float, Unit, Hex]] = None
        for dest in paths:
            enemy = state.blocking_unit_at(dest, Side.UN)
            if enemy:
                value = close_assault_heuristic(unit, enemy)
                if enemy.pos and enemy.pos.distance(state.generator) <= 1:
                    value += 25
                candidate = (value, enemy, dest)
                if best_ca is None or candidate[0] > best_ca[0]:
                    best_ca = candidate

        empty_destinations = [
            h
            for h in paths
            if not occupied_friendly(state, h, Side.WEB, exclude=unit.id)
            and state.blocking_unit_at(h, Side.UN) is None
        ]
        if not empty_destinations:
            empty_destinations = [unit.pos]
        best_empty = max(
            empty_destinations,
            key=lambda h: (local_web_position_score(state, unit, h), h.label()),
        )
        empty_score = local_web_position_score(state, unit, best_empty)

        # Close Assault only when it is materially attractive or urgently
        # protects the Generator; otherwise preserve the infantry for fire.
        if best_ca is not None and best_ca[0] > 3.5 and best_ca[0] + evaluate_state(state) >= empty_score - 2:
            _, enemy, dest = best_ca
            origin = unit.pos
            reveal(state, unit, "moved")
            state.log(f"Web Movement: {unit.id} moves {origin.label()} -> {dest.label()} to Close Assault.")
            resolve_close_assault(state, unit, enemy)
            continue

        if best_empty != unit.pos:
            origin = unit.pos
            unit.pos = best_empty
            reveal(state, unit, "moved")
            state.log(
                f"Web Movement: {unit.id} moves {origin.label()} -> {best_empty.label()} "
                f"({origin.distance(best_empty)} hexes)."
            )


def estimated_result_utility(
    state: GameState,
    attackers: Sequence[Unit],
    defender: Unit,
    result: str,
) -> float:
    target_value = defender.spec.material_value
    if defender.pos and defender.pos.distance(state.generator) <= 2:
        target_value += (3 - defender.pos.distance(state.generator)) * 18

    distances = {u.id: ranged_distance(u, defender) for u in attackers}
    vulnerable = [
        u
        for u in attackers
        if not attacker_immune_to_adverse_result(u, defender, result, distances[u.id])
    ]

    if result == "DE":
        return target_value
    if result == "DUST":
        return 0.0 if defender_ignores_result(defender, result) else target_value * 0.22
    if result == "DR2":
        return 0.0 if defender_ignores_result(defender, result) else target_value * 0.20
    if result == "AE":
        return -sum(u.spec.material_value for u in vulnerable)
    if result == "AR2":
        return -sum(u.spec.material_value for u in vulnerable) * 0.14
    if result == "EX":
        losses = choose_exchange_losses(vulnerable, printed_combat_strength(defender))
        return target_value - sum(u.spec.material_value for u in losses)
    return 0.0


def candidate_attack_groups(attackers: Sequence[Unit]) -> List[Tuple[Unit, ...]]:
    attackers = sorted(attackers, key=lambda u: (-u.spec.combat, u.id))
    groups: Set[Tuple[str, ...]] = set()

    def add(group: Iterable[Unit]) -> None:
        ids = tuple(sorted(u.id for u in group))
        if ids:
            groups.add(ids)

    for u in attackers:
        add([u])
    for n in range(2, min(4, len(attackers)) + 1):
        for combo in itertools.combinations(attackers, n):
            add(combo)
    for n in range(2, len(attackers) + 1):
        add(attackers[:n])
    add(attackers)

    by_id = {u.id: u for u in attackers}
    return [tuple(by_id[uid] for uid in ids) for ids in sorted(groups)]


def expected_attack_utility(state: GameState, attackers: Sequence[Unit], defender: Unit) -> float:
    attack_cs = sum(effective_combat_strength(state, u) for u in attackers)
    defence_cs = effective_combat_strength(state, defender)
    column = odds_column(attack_cs, defence_cs)
    return sum(
        estimated_result_utility(state, attackers, defender, result)
        for result in CRT[column]
    ) / 6.0


def web_ranged_phase(state: GameState) -> None:
    available: Set[str] = {
        u.id
        for u in state.active_units(Side.WEB)
        if u.spec.can_ranged_attack and u.spec.range > 0
    }

    attack_number = 0
    while available:
        best: Optional[Tuple[float, Tuple[Unit, ...], Unit]] = None
        for defender in state.active_units(Side.UN):
            in_range = [
                state.unit(uid)
                for uid in available
                if can_ranged_attack(state, state.unit(uid), defender)
            ]
            for group in candidate_attack_groups(in_range):
                utility = expected_attack_utility(state, group, defender)
                # Slightly favour acting rather than hoarding shots at equal EV.
                utility += 0.03 * len(group)
                if best is None or utility > best[0]:
                    best = (utility, group, defender)

        if best is None or best[0] <= 0.15:
            break
        _, group, defender = best
        attack_number += 1
        state.log(f"Web Ranged Combat #{attack_number}: expected-value attack selected.")
        resolve_ranged_attack(state, [u.id for u in group], defender.id)
        for u in group:
            available.discard(u.id)

    if attack_number == 0:
        state.log("Web Ranged Combat Phase: no attack has positive expected value.")


def run_web_turn(state: GameState) -> None:
    if state.turn > state.max_turns:
        raise ValueError("the scenario has already ended")
    state.log(f"=== WEB PLAYER-TURN, GAME-TURN {state.turn} ===")
    web_compulsion_phase(state)
    web_reinforcement_phase(state)
    web_movement_phase(state)
    web_ranged_phase(state)
    for u in state.active_units(Side.WEB):
        if u.dust:
            u.dust = False
            state.log(f"DUST removed from {u.id} at the end of the Web player-turn.")
    state.log(f"=== END WEB PLAYER-TURN {state.turn} ===")


# ---------------------------------------------------------------------------
# Drop compulsion and human-side helpers
# ---------------------------------------------------------------------------


def parse_assignments(text: str) -> List[Tuple[str, Hex]]:
    result: List[Tuple[str, Hex]] = []
    for item in text.split(","):
        if "=" not in item:
            raise ValueError(f"expected UNIT=HEX in {item!r}")
        uid, h = item.split("=", 1)
        result.append((uid.strip().upper(), Hex.parse(h.strip())))
    if not result:
        raise ValueError("no units supplied")
    return result


def axial_deltas(radius: int) -> List[Hex]:
    result: List[Hex] = []
    for q in range(-radius, radius + 1):
        for r in range(-radius, radius + 1):
            h = Hex(q, r)
            if Hex(0, 0).distance(h) <= radius:
                result.append(h)
    return result


def place_drop_with_compulsion(state: GameState, assignments: List[Tuple[str, Hex]]) -> None:
    if len(assignments) > 3:
        raise ValueError("a single drop contains at most three units")
    units = [state.unit(uid) for uid, _ in assignments]
    if any(u.side != Side.UN for u in units):
        raise ValueError("only U.N. units may be dropped")
    if any(u.eliminated for u in units):
        raise ValueError("an eliminated U.N. unit cannot be dropped")

    targets = [h for _, h in assignments]
    for h in targets:
        if not state.board.is_valid(h):
            raise ValueError(f"drop target {h.label()} is off the configured map")

    eligible = (
        not state.compulsion_broken
        and any(h.distance(state.generator) <= 2 for h in targets)
    )

    chosen_targets = targets
    if eligible:
        alternatives: List[Tuple[float, List[Hex], bool]] = []
        for delta in axial_deltas(3):
            shifted = [h.add(delta) for h in targets]
            if not all(state.board.is_valid(h) for h in shifted):
                continue
            if len(set(shifted)) != len(shifted):
                continue
            lands_on_web = any(state.blocking_unit_at(h, Side.WEB) for h in shifted)
            score = 0.0
            for unit, original, h in zip(units, targets, shifted):
                score += (h.distance(state.generator) - original.distance(state.generator)) * 45
                if state.board.terrain(h) == Terrain.CLIFF:
                    score += unit.spec.material_value * 0.20
                # The formation remains intact because a single axial delta is used.
            alternatives.append((score, shifted, lands_on_web))

        safe = [x for x in alternatives if not x[2]]
        pool = safe if safe else alternatives
        if pool:
            _, chosen_targets, _ = max(pool, key=lambda x: (x[0], [h.label() for h in x[1]]))
            if chosen_targets != targets:
                state.log(
                    "Drop Compulsion: target formation "
                    + ",".join(h.label() for h in targets)
                    + " is displaced to "
                    + ",".join(h.label() for h in chosen_targets)
                    + "."
                )
    else:
        state.log("Drop Compulsion: not available for this drop.")

    for unit, destination in zip(units, chosen_targets):
        unit.pos = destination
        unit.dropped_this_turn = True
        unit.dust = False
        state.log(f"{unit.id} lands at {destination.label()}.")
        if not apply_un_terrain_entry(state, unit, destination, "drop"):
            continue
        enemy = state.blocking_unit_at(destination, Side.WEB)
        if enemy and unit.active:
            resolve_close_assault(state, unit, enemy)
    state.update_compulsion_status()


def end_un_turn(state: GameState) -> None:
    for u in state.active_units(Side.UN):
        if u.dust:
            u.dust = False
            state.log(f"DUST removed from {u.id} at the end of the U.N. player-turn.")
        u.dropped_this_turn = False
    for u in state.units.values():
        u.reinforced_this_turn = False
    state.update_compulsion_status()
    state.log(f"=== END U.N. PLAYER-TURN {state.turn} ===")
    state.turn += 1
    if state.turn <= state.max_turns:
        state.log(f"Game-Turn marker advances to {state.turn}.")
    else:
        state.log(victory_status(state))


def victory_status(state: GameState) -> str:
    if state.scenario != "introductory":
        return "Victory check: this program only automates the Introductory conditions."
    if state.turn <= state.max_turns:
        if state.compulsion_broken:
            return (
                "Current result: the U.N. has reached the Generator at least once; "
                "it must occupy it at the end of Game-Turn 4 for a U.N. victory, otherwise a draw."
            )
        return "Current result: the Web still prevents contact with the Generator."
    if state.un_on_generator():
        return "FINAL RESULT: U.N. victory - a U.N. unit occupies the Generator after Game-Turn 4."
    if state.compulsion_broken:
        return "FINAL RESULT: draw - the U.N. reached the Generator, but does not occupy it after Game-Turn 4."
    return "FINAL RESULT: Web victory - no U.N. unit ever reached the Generator."


# ---------------------------------------------------------------------------
# Command-line interface
# ---------------------------------------------------------------------------


def cmd_new(args: argparse.Namespace) -> None:
    path = Path(args.state)
    if path.exists() and not args.force:
        raise SystemExit(f"refusing to overwrite {path}; use --force")
    state = create_intro_state(Hex.parse(args.generator), args.seed)
    save_state(state, path, make_backup=False)
    print(f"Created {path}")
    print("Place the Generator face-up and the following Web counters face-down:")
    for u in sorted(state.active_units(Side.WEB), key=lambda x: (x.pos.label(), x.id)):
        assert u.pos is not None
        print(f"  {u.id} at {u.pos.label()}")
    print("The public counter IDs reveal no identity.  Use 'show' without --omniscient during play.")


def cmd_show(args: argparse.Namespace) -> None:
    display_state(load_state(Path(args.state)), args.omniscient)


def cmd_place(args: argparse.Namespace) -> None:
    path = Path(args.state)
    state = load_state(path)
    unit = state.unit(args.unit)
    destination = Hex.parse(args.hex)
    if not state.board.is_valid(destination):
        raise SystemExit(f"{destination.label()} is off the configured map")
    if unit.eliminated:
        raise SystemExit(f"{unit.id} is eliminated; use the state file or reinforcement rules to restore it")
    if occupied_friendly(state, destination, unit.side, exclude=unit.id):
        raise SystemExit(f"a friendly combat unit already occupies {destination.label()}")
    old = unit.pos.label() if unit.pos else "off map"
    unit.pos = destination
    state.log(f"Manual placement: {unit.id} {old} -> {destination.label()}.")
    state.update_compulsion_status()
    save_state(state, path)


def cmd_eliminate(args: argparse.Namespace) -> None:
    path = Path(args.state)
    state = load_state(path)
    eliminate(state, state.unit(args.unit), "manual update")
    save_state(state, path)


def cmd_dust(args: argparse.Namespace) -> None:
    path = Path(args.state)
    state = load_state(path)
    unit = state.unit(args.unit)
    unit.dust = args.value == "on"
    state.log(f"Manual update: DUST {'placed on' if unit.dust else 'removed from'} {unit.id}.")
    save_state(state, path)


def cmd_terrain(args: argparse.Namespace) -> None:
    path = Path(args.state)
    state = load_state(path)
    hexes = {Hex.parse(x) for x in args.hexes}
    if args.kind == "plain":
        state.board.cliff.difference_update(hexes)
        state.board.incline.difference_update(hexes)
    elif args.kind == "cliff":
        state.board.cliff.update(hexes)
        state.board.incline.difference_update(hexes)
    elif args.kind == "incline":
        state.board.incline.update(hexes)
        state.board.cliff.difference_update(hexes)
    state.log(f"Terrain update: {args.kind} at {', '.join(sorted(h.label() for h in hexes))}.")
    save_state(state, path)


def cmd_drop(args: argparse.Namespace) -> None:
    path = Path(args.state)
    state = load_state(path)
    place_drop_with_compulsion(state, parse_assignments(args.assignments))
    save_state(state, path)


def cmd_ai_turn(args: argparse.Namespace) -> None:
    path = Path(args.state)
    state = load_state(path)
    run_web_turn(state)
    save_state(state, path)


def cmd_un_attack(args: argparse.Namespace) -> None:
    path = Path(args.state)
    state = load_state(path)
    attackers = [x.strip().upper() for x in args.attackers.split(",") if x.strip()]
    if any(state.unit(uid).side != Side.UN for uid in attackers):
        raise SystemExit("un-attack requires U.N. attackers")
    if state.unit(args.defender).side != Side.WEB:
        raise SystemExit("un-attack requires a Web defender")
    resolve_ranged_attack(state, attackers, args.defender.upper(), args.die)
    save_state(state, path)


def cmd_un_assault(args: argparse.Namespace) -> None:
    path = Path(args.state)
    state = load_state(path)
    attacker = state.unit(args.attacker)
    defender = state.unit(args.defender)
    if attacker.side != Side.UN or defender.side != Side.WEB:
        raise SystemExit("un-assault requires a U.N. attacker and Web defender")
    if attacker.pos is None or defender.pos is None:
        raise SystemExit("both units must be on the map")
    if attacker.pos.distance(defender.pos) != 1:
        raise SystemExit("the attacker must begin adjacent to the defender")
    dice = None
    if args.dice:
        try:
            dice = [int(x) for x in args.dice.split(",")]
        except ValueError as exc:
            raise SystemExit("--dice must be comma-separated values 1..6") from exc
    resolve_close_assault(state, attacker, defender, dice)
    save_state(state, path)


def cmd_end_un(args: argparse.Namespace) -> None:
    path = Path(args.state)
    state = load_state(path)
    end_un_turn(state)
    save_state(state, path)


def cmd_demo(args: argparse.Namespace) -> None:
    state = create_intro_state(Hex.parse("1413"), 1978)
    # A compact sample raid near the Generator.
    sample = [
        ("H1", "1111"),
        ("H2", "1211"),
        ("H3", "1212"),
        ("L1", "1012"),
        ("L2", "1112"),
        ("T1", "0912"),
    ]
    for uid, text in sample:
        state.unit(uid).pos = Hex.parse(text)
    print("Initial demonstration position (omniscient display):")
    display_state(state, omniscient=True)
    run_web_turn(state)
    print("\nAfter the AI's Web player-turn:")
    display_state(state, omniscient=True)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="AI opponent/referee assistant for OLYMPICA's Introductory Scenario",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Run 'python3 olympica_ai.py demo' for a no-file demonstration.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("new", help="create a new Introductory Scenario state")
    p.add_argument("state")
    p.add_argument("--generator", default="1413", help="Generator hex (default: 1413)")
    p.add_argument("--seed", type=int, default=1978)
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=cmd_new)

    p = sub.add_parser("show", help="display a saved state")
    p.add_argument("state")
    p.add_argument("--omniscient", action="store_true", help="reveal all Web identities")
    p.set_defaults(func=cmd_show)

    p = sub.add_parser("place", help="manually place or move a unit")
    p.add_argument("state")
    p.add_argument("unit")
    p.add_argument("hex")
    p.set_defaults(func=cmd_place)

    p = sub.add_parser("eliminate", help="manually eliminate a unit")
    p.add_argument("state")
    p.add_argument("unit")
    p.set_defaults(func=cmd_eliminate)

    p = sub.add_parser("dust", help="manually add or remove a DUST marker")
    p.add_argument("state")
    p.add_argument("unit")
    p.add_argument("value", choices=("on", "off"))
    p.set_defaults(func=cmd_dust)

    p = sub.add_parser("terrain", help="mark map hexes as plain, cliff or incline")
    p.add_argument("state")
    p.add_argument("kind", choices=("plain", "cliff", "incline"))
    p.add_argument("hexes", nargs="+")
    p.set_defaults(func=cmd_terrain)

    p = sub.add_parser("drop", help="place one U.N. drop and let the Web AI compel it")
    p.add_argument("state")
    p.add_argument("assignments", help="for example H1=1110,H2=1210,H3=1111")
    p.set_defaults(func=cmd_drop)

    p = sub.add_parser("ai-turn", help="run and save the Web player-turn")
    p.add_argument("state")
    p.set_defaults(func=cmd_ai_turn)

    p = sub.add_parser("un-attack", help="resolve a U.N. ranged attack")
    p.add_argument("state")
    p.add_argument("attackers", help="comma-separated U.N. unit IDs")
    p.add_argument("defender", help="Web counter ID")
    p.add_argument("--die", type=int, choices=range(1, 7))
    p.set_defaults(func=cmd_un_attack)

    p = sub.add_parser("un-assault", help="resolve a U.N. Close Assault")
    p.add_argument("state")
    p.add_argument("attacker")
    p.add_argument("defender")
    p.add_argument("--dice", help="optional comma-separated physical die sequence")
    p.set_defaults(func=cmd_un_assault)

    p = sub.add_parser("end-un-turn", help="remove U.N. DUST and advance the turn marker")
    p.add_argument("state")
    p.set_defaults(func=cmd_end_un)

    p = sub.add_parser("demo", help="run a self-contained demonstration")
    p.set_defaults(func=cmd_demo)

    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        args.func(args)
        return 0
    except ValueError as exc:
        parser.error(str(exc))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
