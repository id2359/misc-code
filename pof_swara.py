#!/usr/bin/env python3
"""
Polytopic Fuzzy SWARA (POF-SWARA) reference implementation.

Pipeline
--------
1. Linguistic scale -> polytopic fuzzy numbers (PoFN)  [the "fuzzy rules"]
2. experts.csv: each expert rates each criterion's importance linguistically,
   experts carry a weight.
3. Aggregate expert ratings per criterion with the polytopic fuzzy weighted
   average (POFWA) operator -> one PoFN per criterion.
4. Score function -> crisp importance; sort descending; comparative
   importance s_j = S_{j-1} - S_j; SWARA recursion -> weight vector w.
5. alternatives.csv (crisp performance matrix) + criteria.csv (benefit/cost)
   -> WASPAS ranking using w.

Usage:  python pof_swara.py [--q 3] [--lam 0.5] [--dir .]

Only numpy is required.
"""
from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from pathlib import Path

import numpy as np


# --------------------------------------------------------------------------
# 1. Polytopic fuzzy numbers
# --------------------------------------------------------------------------
@dataclass(frozen=True)
class PoFN:
    """Polytopic fuzzy number (mu, eta, nu) subject to mu^q + eta^q + nu^q <= 1.

    mu  : positive membership
    eta : neutral membership
    nu  : negative membership
    q   : rung.  q=1 -> picture fuzzy, q=2 -> spherical fuzzy, q>=3 polytopic.
    """
    mu: float
    eta: float
    nu: float
    q: int = 3

    def __post_init__(self):
        for v in (self.mu, self.eta, self.nu):
            if not 0.0 <= v <= 1.0:
                raise ValueError(f"membership out of [0,1]: {self}")
        if self.constraint() > 1.0 + 1e-12:
            raise ValueError(
                f"violates polytopic constraint for q={self.q}: "
                f"mu^q+eta^q+nu^q={self.constraint():.4f} > 1  ({self})"
            )

    def constraint(self) -> float:
        return self.mu**self.q + self.eta**self.q + self.nu**self.q

    def refusal(self) -> float:
        """Refusal degree pi = (1 - mu^q - eta^q - nu^q)^(1/q)."""
        return max(0.0, 1.0 - self.constraint()) ** (1.0 / self.q)

    def score(self) -> float:
        """Score function S in [0,1]: S = (2 + mu^q - eta^q - nu^q) / 3.

        One of several score functions used in spherical/polytopic literature;
        the choice materially affects s_j, so it is isolated here.
        """
        q = self.q
        return (2.0 + self.mu**q - self.eta**q - self.nu**q) / 3.0

    def accuracy(self) -> float:
        """Accuracy H = mu^q + eta^q + nu^q  (tie-break for equal scores)."""
        return self.constraint()

    def __repr__(self):
        return f"({self.mu:.3f}, {self.eta:.3f}, {self.nu:.3f})"


def pofwa(items: list[PoFN], weights: np.ndarray, q: int) -> PoFN:
    """Polytopic fuzzy weighted average (POFWA) aggregation operator.

        mu  = (1 - prod (1 - mu_i^q)^w_i)^(1/q)
        eta = prod eta_i^w_i
        nu  = prod nu_i^w_i
    """
    w = np.asarray(weights, dtype=float)
    w = w / w.sum()
    mu = np.array([p.mu for p in items])
    eta = np.array([p.eta for p in items])
    nu = np.array([p.nu for p in items])
    agg_mu = (1.0 - np.prod((1.0 - mu**q) ** w)) ** (1.0 / q)
    agg_eta = float(np.prod(eta**w))
    agg_nu = float(np.prod(nu**w))
    return PoFN(float(agg_mu), agg_eta, agg_nu, q)


def pofwg(items: list[PoFN], weights: np.ndarray, q: int) -> PoFN:
    """Polytopic fuzzy weighted geometric (POFWG) operator (dual of POFWA).

        mu  = prod mu_i^w_i
        eta = (1 - prod (1 - eta_i^q)^w_i)^(1/q)
        nu  = (1 - prod (1 - nu_i^q)^w_i)^(1/q)
    """
    w = np.asarray(weights, dtype=float)
    w = w / w.sum()
    mu = np.array([p.mu for p in items])
    eta = np.array([p.eta for p in items])
    nu = np.array([p.nu for p in items])
    agg_mu = float(np.prod(mu**w))
    agg_eta = (1.0 - np.prod((1.0 - eta**q) ** w)) ** (1.0 / q)
    agg_nu = (1.0 - np.prod((1.0 - nu**q) ** w)) ** (1.0 / q)
    return PoFN(agg_mu, float(agg_eta), float(agg_nu), q)


# --------------------------------------------------------------------------
# 2. Linguistic scale  ("fuzzy rules": term -> (mu, eta, nu))
# --------------------------------------------------------------------------
# Deliberately includes terms with large neutral membership (M, H) so that the
# scale is NOT admissible as picture fuzzy (q=1) -- this is the point of using
# a higher rung.
LINGUISTIC_SCALE: dict[str, tuple[float, float, float]] = {
    "AL": (0.10, 0.15, 0.90),  # absolutely low importance
    "VL": (0.20, 0.25, 0.80),  # very low
    "L":  (0.35, 0.35, 0.65),  # low
    "M":  (0.55, 0.55, 0.55),  # medium  (sum=1.65 > 1 -> not picture fuzzy)
    "H":  (0.70, 0.45, 0.45),  # high    (sum=1.60 > 1 -> not picture fuzzy)
    "VH": (0.80, 0.25, 0.25),  # very high
    "AH": (0.90, 0.15, 0.10),  # absolutely high
}


def build_scale(q: int) -> dict[str, PoFN]:
    """Instantiate the linguistic scale at rung q, validating the constraint."""
    return {k: PoFN(*v, q=q) for k, v in LINGUISTIC_SCALE.items()}


def report_scale_admissibility():
    print("Linguistic scale admissibility by rung q (mu^q+eta^q+nu^q <= 1):")
    print(f"  {'term':4} {'(mu,eta,nu)':22} " + " ".join(f"q={q:<6}" for q in (1, 2, 3, 4)))
    for term, (mu, eta, nu) in LINGUISTIC_SCALE.items():
        vals = []
        for q in (1, 2, 3, 4):
            c = mu**q + eta**q + nu**q
            vals.append(f"{c:5.3f}{'*' if c > 1 else ' '}")
        print(f"  {term:4} ({mu:.2f},{eta:.2f},{nu:.2f})      " + "  ".join(vals))
    print("  (* = violates constraint at that q)\n")


# --------------------------------------------------------------------------
# 3. CSV loading
# --------------------------------------------------------------------------
def load_experts(path: Path):
    """Return (expert_ids, expert_weights, ratings) where
    ratings[criterion][expert] = linguistic term."""
    ratings: dict[str, dict[str, str]] = {}
    expert_w: dict[str, float] = {}
    with path.open() as f:
        for row in csv.DictReader(f):
            e, c, t = row["expert"], row["criterion"], row["importance"].strip()
            expert_w[e] = float(row["expert_weight"])
            ratings.setdefault(c, {})[e] = t
    experts = list(expert_w)
    w = np.array([expert_w[e] for e in experts])
    return experts, w / w.sum(), ratings


def load_criteria(path: Path) -> dict[str, str]:
    with path.open() as f:
        return {r["criterion"]: r["type"].strip().lower() for r in csv.DictReader(f)}


def load_alternatives(path: Path, criteria: list[str]):
    names, rows = [], []
    with path.open() as f:
        for r in csv.DictReader(f):
            names.append(r["alternative"])
            rows.append([float(r[c]) for c in criteria])
    return names, np.array(rows)


# --------------------------------------------------------------------------
# 4. POF-SWARA
# --------------------------------------------------------------------------
def pof_swara(ratings, experts, expert_w, scale, q, verbose=True):
    """Return dict criterion -> weight, plus the ordered SWARA table."""
    # 4a. aggregate each criterion's expert ratings into a single PoFN
    agg: dict[str, PoFN] = {}
    for c, by_expert in ratings.items():
        terms = [by_expert[e] for e in experts]
        agg[c] = pofwa([scale[t] for t in terms], expert_w, q)

    # 4b. score, sort descending (ties broken by accuracy)
    order = sorted(agg, key=lambda c: (agg[c].score(), agg[c].accuracy()), reverse=True)

    # 4c. SWARA recursion
    rows = []
    q_prev = 1.0
    for j, c in enumerate(order):
        S = agg[c].score()
        s = 0.0 if j == 0 else rows[-1]["S"] - S       # comparative importance
        k = 1.0 + s                                     # coefficient
        qj = 1.0 if j == 0 else q_prev / k              # recalculated weight
        rows.append(dict(criterion=c, pofn=agg[c], S=S, s=s, k=k, q=qj))
        q_prev = qj
    total = sum(r["q"] for r in rows)
    for r in rows:
        r["w"] = r["q"] / total

    if verbose:
        print(f"POF-SWARA (q={q})")
        print(f"  {'criterion':12} {'aggregated PoFN':24} {'S':>7} {'s_j':>7} {'k_j':>7} {'q_j':>7} {'w_j':>7}")
        for r in rows:
            print(f"  {r['criterion']:12} {r['pofn']!r:24} {r['S']:7.4f} {r['s']:7.4f} "
                  f"{r['k']:7.4f} {r['q']:7.4f} {r['w']:7.4f}")
        print()
    return {r["criterion"]: r["w"] for r in rows}, rows


# --------------------------------------------------------------------------
# 5. WASPAS evaluation of alternatives with crisp data
# --------------------------------------------------------------------------
def waspas(X: np.ndarray, w: np.ndarray, types: list[str], lam: float = 0.5):
    """Weighted Aggregated Sum Product Assessment.

    Linear normalisation: benefit x/max, cost min/x.
    Q = lam * WSM + (1-lam) * WPM.
    """
    N = np.empty_like(X, dtype=float)
    for j, t in enumerate(types):
        col = X[:, j]
        N[:, j] = col / col.max() if t == "benefit" else col.min() / col
    wsm = (N * w).sum(axis=1)
    wpm = np.prod(N ** w, axis=1)
    Q = lam * wsm + (1 - lam) * wpm
    return N, wsm, wpm, Q


# --------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=".", help="directory containing the CSVs")
    ap.add_argument("--q", type=int, default=3, help="polytopic rung")
    ap.add_argument("--lam", type=float, default=0.5, help="WASPAS lambda")
    args = ap.parse_args()
    d = Path(args.dir)

    report_scale_admissibility()
    scale = build_scale(args.q)
    print(f"Scale instantiated at q={args.q}:")
    for t, p in scale.items():
        print(f"  {t:3} -> {p!r}  score={p.score():.4f}  refusal={p.refusal():.4f}")
    print()

    experts, expert_w, ratings = load_experts(d / "experts.csv")
    print("Experts:", ", ".join(f"{e}({w:.2f})" for e, w in zip(experts, expert_w)), "\n")

    weights, _ = pof_swara(ratings, experts, expert_w, scale, args.q)

    ctypes = load_criteria(d / "criteria.csv")
    criteria = list(weights)                    # SWARA order
    names, X = load_alternatives(d / "alternatives.csv", criteria)
    w = np.array([weights[c] for c in criteria])
    types = [ctypes[c] for c in criteria]

    N, wsm, wpm, Q = waspas(X, w, types, args.lam)
    rank = np.argsort(-Q)

    print(f"WASPAS (lambda={args.lam})  criteria order: {criteria}")
    print(f"  {'alt':8} {'WSM':>8} {'WPM':>8} {'Q':>8}  rank")
    pos = {i: r + 1 for r, i in enumerate(rank)}
    for i, n in enumerate(names):
        print(f"  {n:8} {wsm[i]:8.4f} {wpm[i]:8.4f} {Q[i]:8.4f}  {pos[i]}")
    print("\nRanking:", " > ".join(names[i] for i in rank))


if __name__ == "__main__":
    main()
