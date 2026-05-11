"""
Scaled-up stress test: 48 EBA-style banks, Hałaj-Kok interbank network
reconstruction, Monte Carlo over network realisations.

Builds on firesale2.py.  All three contagion channels (fire sales, funding
withdrawal, counterparty losses) are active.  The actor classes
(AssetMarket, LoanBook, Bank, Coordinator) are imported as-is; only the
data and the driver change.

NEW IN THIS FILE
----------------
1. EBA-style balance-sheet generator
   Produces a sample of 48 heterogeneous banks with realistic distributions
   for size, leverage, and asset mix.  Calibrated to plausible ranges
   (CET1 ratios 8-18%, leverage ratios 3.5-7%, asset sizes spanning two
   orders of magnitude).  Not the real EBA 2018 numbers — for that you
   need to plug in the actual CSV — but the structure is faithful.

2. Hałaj-Kok network reconstruction
   When you know each bank's *aggregate* interbank assets and liabilities
   but not the bilateral exposures (the usual case in public data), HK
   reconstructs a plausible bilateral matrix L_ij subject to:
        sum_j L_ij = A_i   (bank i's total interbank receivables)
        sum_i L_ij = D_j   (bank j's total interbank payables)
        L_ii = 0           (no self-loops)
        L_ij ~ U(0, max_frac * min(remaining_A_i, remaining_D_j))
   Iterative random pair-matching until residuals are exhausted.

3. Monte Carlo driver
   Runs N=100 replications, each with a fresh network reconstruction.
   Reports mean/std of default rate, fraction of system stressed, etc.

USAGE
-----
    python firesale3.py                          # default: shock=0.05, mc=20
    python firesale3.py --shock 0.07 --mc 100    # full WP 861 run

Note: this is *not* the real EBA 2018 calibration.  The balance-sheet
distributions are synthesised to be realistic enough to demonstrate the
algorithm.  To use real EBA data, point `load_eba_data()` at the file.
"""

from __future__ import annotations

import argparse
import math
import statistics
import sys
import time
from dataclasses import dataclass

import numpy as np

# Import the actor classes from firesale2 — they don't need to change.
sys.path.insert(0, "/home/claude")
from firesale2 import (
    AssetMarket, LoanBook, Bank, Coordinator,
    Holding, InterbankLoan,
)


# ---------------------------------------------------------------------------
# (1) EBA-style balance-sheet generator
# ---------------------------------------------------------------------------

@dataclass
class BankSpec:
    """Spec for a single bank, used to construct the actor at runtime."""
    bank_id: str
    total_assets: float            # in billions of currency units
    leverage_ratio: float          # equity / total_assets
    govies_share: float            # fraction of tradable holdings in govies
    cash_share: float              # cash / total_assets
    interbank_recv_share: float    # interbank receivables / total_assets
    interbank_pay_share: float     # interbank payables / total_assets


def generate_eba_sample(n_banks: int = 48, seed: int = 42) -> list[BankSpec]:
    """
    Synthesise a heterogeneous EU-SIB-like sample.

    Distributional choices, broadly matching EBA 2018:
      - log-normal size distribution: median ~€500bn, range €50bn-€2T
      - leverage ratio: Beta(4, 60) shifted to [3.5%, 7%] — most banks
        clustered around 4.5-5%, a few stressed banks lower
      - govies share of tradables: U(0.25, 0.75) — banks vary in their
        sovereign exposure
      - cash share: roughly 5-12% of assets
      - interbank receivables and payables each 4-12% of assets
    """
    rng = np.random.default_rng(seed)
    specs = []

    # Size: log-normal centered around log(500), range capped
    log_sizes = rng.normal(loc=math.log(500), scale=1.0, size=n_banks)
    sizes = np.clip(np.exp(log_sizes), 50, 2000)

    for i in range(n_banks):
        # Leverage: Beta(2, 5) on [0, 1] has mean 2/7 ≈ 0.286.
        # Map to [3.5%, 7%]:  lev = 0.035 + 0.035 * Beta(2,5).
        # This gives mean ~ 4.5%, mode around 4.4%, range 3.5-7%.
        leverage = 0.035 + 0.035 * rng.beta(2, 5)
        leverage = float(np.clip(leverage, 0.035, 0.07))
        spec = BankSpec(
            bank_id=f"B{i:02d}",
            total_assets=float(sizes[i]),
            leverage_ratio=leverage,
            govies_share=float(rng.uniform(0.25, 0.75)),
            cash_share=float(rng.uniform(0.05, 0.12)),
            interbank_recv_share=float(rng.uniform(0.04, 0.12)),
            interbank_pay_share=float(rng.uniform(0.04, 0.12)),
        )
        specs.append(spec)

    # Normalise interbank totals: sum(receivables) must equal sum(payables)
    # across the system, so that the network is balanced.
    total_recv = sum(s.total_assets * s.interbank_recv_share for s in specs)
    total_pay = sum(s.total_assets * s.interbank_pay_share for s in specs)
    scale = total_recv / total_pay
    for s in specs:
        s.interbank_pay_share *= scale

    return specs


# ---------------------------------------------------------------------------
# (2) Hałaj-Kok interbank network reconstruction
# ---------------------------------------------------------------------------

def reconstruct_network_halaj_kok(
    specs: list[BankSpec],
    max_bilateral_frac: float = 0.20,
    seed: int | None = None,
    max_iters: int = 10_000,
) -> list[InterbankLoan]:
    """
    Reconstruct a plausible bilateral interbank network from aggregate
    receivables and payables, using the Hałaj-Kok iterative random
    pair-matching algorithm.

    Algorithm:
        - row_target[i] = aggregate receivables of bank i
        - col_target[j] = aggregate payables of bank j
        - Start with empty matrix L.  Maintain row_remaining and col_remaining.
        - Iterate:
            * pick random (i, j) with row_remaining[i] > 0 and col_remaining[j] > 0
            * draw amount = U(0, max_bilateral_frac * min(remaining))
            * add to L[i, j]; decrement remainings
        - Stop when all remainings exhausted (or max_iters reached).
        - Any tiny residuals (< 1% of total) are absorbed; large residuals
          indicate a degenerate configuration and would be a bug.

    Returns a list of InterbankLoan objects (only non-zero entries).
    """
    rng = np.random.default_rng(seed)
    n = len(specs)

    row_target = np.array([s.total_assets * s.interbank_recv_share
                           for s in specs])
    col_target = np.array([s.total_assets * s.interbank_pay_share
                           for s in specs])
    # Numerical: row and col totals should match (we balanced them in
    # generate_eba_sample), but FP roundoff means they might be off by
    # 1e-10.  Force exact equality.
    col_target *= row_target.sum() / col_target.sum()

    L = np.zeros((n, n))
    row_rem = row_target.copy()
    col_rem = col_target.copy()

    tol = 1e-3 * row_target.sum()

    for _ in range(max_iters):
        if row_rem.sum() < tol:
            break
        # Pick a random row with remaining capacity
        active_rows = np.where(row_rem > 1e-9)[0]
        active_cols = np.where(col_rem > 1e-9)[0]
        if len(active_rows) == 0 or len(active_cols) == 0:
            break
        i = rng.choice(active_rows)
        # Pick a random column != i with remaining capacity
        candidate_cols = active_cols[active_cols != i]
        if len(candidate_cols) == 0:
            # Only column with capacity is the row itself — distribute
            # this row's residual proportionally to other columns to
            # avoid getting stuck.  This is a pragmatic deviation from
            # strict HK; rarely triggered.
            other_cols = np.arange(n) != i
            weights = col_target[other_cols]
            if weights.sum() > 0:
                amounts = row_rem[i] * weights / weights.sum()
                L[i, other_cols] += amounts
                col_rem[other_cols] -= amounts
                row_rem[i] = 0
            else:
                row_rem[i] = 0
            continue
        j = rng.choice(candidate_cols)
        cap = min(row_rem[i], col_rem[j])
        amount = float(rng.uniform(0, max_bilateral_frac * cap))
        L[i, j] += amount
        row_rem[i] -= amount
        col_rem[j] -= amount

    # Final residual cleanup: distribute any small residuals proportionally
    if row_rem.sum() > tol:
        # Pro-rate the remaining row residuals across the column residuals
        for i in range(n):
            if row_rem[i] < 1e-9:
                continue
            other = np.arange(n) != i
            weights = np.maximum(col_rem[other], 0)
            if weights.sum() > 0:
                amounts = row_rem[i] * weights / weights.sum()
                L[i, other] += amounts
                col_rem[other] -= amounts
                row_rem[i] = 0

    # Convert nonzero entries to InterbankLoan objects
    loans = []
    loan_idx = 0
    for i in range(n):
        for j in range(n):
            if L[i, j] > 0.5:    # threshold out trivial entries
                loans.append(InterbankLoan(
                    loan_id=f"L{loan_idx:04d}",
                    lender=specs[i].bank_id,
                    borrower=specs[j].bank_id,
                    principal=float(L[i, j]),
                ))
                loan_idx += 1
    return loans


# ---------------------------------------------------------------------------
# Building actors from specs
# ---------------------------------------------------------------------------

def build_actors_from_specs(specs: list[BankSpec],
                            loans: list[InterbankLoan]):
    """
    Compose the actor system from balance-sheet specs and an interbank
    network.  Returns (market_ref, loanbook_ref, bank_refs).
    """
    market_caps = {"govies": 1_000_000.0, "corporates": 1_000_000.0}
    initial_prices = {"govies": 1.0, "corporates": 1.0}
    market = AssetMarket.start(prices=initial_prices,
                               market_caps=market_caps)
    loanbook = LoanBook.start(loans=loans)

    # Compute each bank's interbank receivables and payables from the
    # actual reconstructed loans (which may differ slightly from spec
    # targets due to HK numerical residuals).
    recv_by_bank: dict[str, float] = {s.bank_id: 0.0 for s in specs}
    pay_by_bank: dict[str, float] = {s.bank_id: 0.0 for s in specs}
    for ln in loans:
        recv_by_bank[ln.lender] += ln.principal
        pay_by_bank[ln.borrower] += ln.principal

    bank_refs = {}
    for s in specs:
        A = s.total_assets
        E = A * s.leverage_ratio
        L_total = A - E
        # Liabilities decomposition: interbank payables + external debt
        interbank_pay = pay_by_bank[s.bank_id]
        external_debt = L_total - interbank_pay
        # Assets decomposition: interbank receivables + cash + tradables
        interbank_recv = recv_by_bank[s.bank_id]
        cash = A * s.cash_share
        tradables_value = A - interbank_recv - cash
        govies_value = tradables_value * s.govies_share
        corp_value = tradables_value - govies_value
        holdings = [
            Holding("govies", govies_value),       # price=1 so qty=value
            Holding("corporates", corp_value),
        ]
        ref = Bank.start(bank_id=s.bank_id, cash=cash, holdings=holdings,
                         external_debt=external_debt)
        bank_refs[s.bank_id] = ref

    return market, loanbook, bank_refs


def teardown_actors(market, loanbook, bank_refs):
    market.stop()
    loanbook.stop()
    for ref in bank_refs.values():
        ref.stop()


# ---------------------------------------------------------------------------
# (3) Monte Carlo driver
# ---------------------------------------------------------------------------

@dataclass
class ReplicationResult:
    seed: int
    n_defaults: int
    n_banks: int
    final_govies_price: float
    final_corp_price: float
    total_funding_pulled: float
    total_counterparty_losses: float
    total_fire_sale_volume: float
    n_steps: int


def run_one_replication(specs: list[BankSpec], shock_asset: str,
                        shock_size: float, network_seed: int,
                        max_steps: int = 20) -> ReplicationResult:
    """One Monte Carlo replication: reconstruct a network with `network_seed`,
    build the system, apply the shock, run until quiescent or max_steps."""
    loans = reconstruct_network_halaj_kok(specs, seed=network_seed)
    market, loanbook, banks = build_actors_from_specs(specs, loans)
    coord = Coordinator(market, loanbook, banks)

    market.ask(("shock", shock_asset, shock_size))

    funding = 0.0
    counterparty = 0.0
    firesale_total = 0.0
    last_step = 0
    for t in range(1, max_steps + 1):
        r = coord.step(t)
        last_step = t
        funding += r.funding_pulled
        counterparty += r.counterparty_losses
        firesale_total += sum(r.fire_sale_volume.values())
        # Quiescence: no activity at all this step
        if (not r.fire_sale_volume
                and r.funding_pulled < 1e-6
                and r.counterparty_losses < 1e-6):
            break

    final_prices = market.ask("get_prices")
    n_defaults = len(coord.previously_insolvent)
    result = ReplicationResult(
        seed=network_seed,
        n_defaults=n_defaults,
        n_banks=len(specs),
        final_govies_price=final_prices["govies"],
        final_corp_price=final_prices["corporates"],
        total_funding_pulled=funding,
        total_counterparty_losses=counterparty,
        total_fire_sale_volume=firesale_total,
        n_steps=last_step,
    )
    teardown_actors(market, loanbook, banks)
    return result


def run_monte_carlo(n_replications: int, shock_size: float,
                    n_banks: int = 48, balance_sheet_seed: int = 42,
                    verbose: bool = True) -> list[ReplicationResult]:
    """Run N replications.  Balance sheets are fixed across replications
    (seeded once); only the interbank network reconstruction varies.
    This matches the Oxford methodology: average over network uncertainty,
    not over balance-sheet uncertainty."""
    specs = generate_eba_sample(n_banks=n_banks, seed=balance_sheet_seed)

    if verbose:
        print(f"Generated {len(specs)} banks.  Aggregate stats:")
        total_assets = sum(s.total_assets for s in specs)
        mean_lev = sum(s.leverage_ratio for s in specs) / len(specs)
        total_ib = sum(s.total_assets * s.interbank_recv_share
                       for s in specs)
        print(f"  total assets:    {total_assets:>10.1f} bn")
        print(f"  mean leverage:   {mean_lev:>10.2%}")
        print(f"  interbank total: {total_ib:>10.1f} bn "
              f"({total_ib/total_assets:.1%} of system assets)")
        print(f"\nRunning {n_replications} replications with shock={shock_size:.0%} "
              f"to govies...\n")

    results = []
    t_start = time.time()
    for rep in range(n_replications):
        r = run_one_replication(specs, shock_asset="govies",
                                shock_size=shock_size,
                                network_seed=1000 + rep)
        results.append(r)
        if verbose and (rep + 1) % 5 == 0:
            elapsed = time.time() - t_start
            rate = (rep + 1) / elapsed
            eta = (n_replications - rep - 1) / rate
            mean_def = sum(x.n_defaults for x in results) / len(results)
            print(f"  rep {rep+1:3d}/{n_replications}  "
                  f"mean_defaults={mean_def:5.2f}/{n_banks}  "
                  f"rate={rate:.1f}/s  eta={eta:5.1f}s")

    if verbose:
        print(f"\nDone in {time.time() - t_start:.1f}s")
    return results


def summarise(results: list[ReplicationResult]) -> None:
    n_banks = results[0].n_banks
    defaults = [r.n_defaults for r in results]
    default_rates = [d / n_banks for d in defaults]
    fire = [r.total_fire_sale_volume for r in results]
    funding = [r.total_funding_pulled for r in results]
    ctpty = [r.total_counterparty_losses for r in results]
    prices_g = [r.final_govies_price for r in results]
    prices_c = [r.final_corp_price for r in results]
    steps = [r.n_steps for r in results]

    print(f"\n{'='*78}")
    print(f"MONTE CARLO SUMMARY ({len(results)} replications)")
    print(f"{'='*78}")

    def stat(label, xs, fmt="{:>9.2f}"):
        mn, mx = min(xs), max(xs)
        mean = sum(xs) / len(xs)
        sd = statistics.stdev(xs) if len(xs) > 1 else 0.0
        print(f"  {label:30s}  mean={fmt.format(mean)}  "
              f"sd={fmt.format(sd)}  min={fmt.format(mn)}  max={fmt.format(mx)}")

    stat("defaults",            defaults, "{:>9.1f}")
    stat("default rate (frac)", default_rates, "{:>9.2%}")
    stat("final govies price",  prices_g, "{:>9.4f}")
    stat("final corp price",    prices_c, "{:>9.4f}")
    stat("fire-sale volume",    fire,    "{:>9.0f}")
    stat("funding pulled",      funding, "{:>9.0f}")
    stat("counterparty losses", ctpty,   "{:>9.0f}")
    stat("simulation steps",    steps,   "{:>9.1f}")

    # Systemic-event rate (Gai-Kapadia: 5% of banks defaulted)
    threshold = max(1, int(0.05 * n_banks))
    systemic_count = sum(1 for d in defaults if d >= threshold)
    print(f"\n  systemic-event rate (≥{threshold} defaults): "
          f"{systemic_count}/{len(results)} = "
          f"{systemic_count/len(results):.0%}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(
        description="Scaled-up multi-channel stress test")
    ap.add_argument("--shock", type=float, default=0.05,
                    help="initial shock fraction on govies (default: 0.05)")
    ap.add_argument("--mc", type=int, default=20,
                    help="number of Monte Carlo replications (default: 20)")
    ap.add_argument("--banks", type=int, default=48,
                    help="number of banks (default: 48 like EBA 2018)")
    ap.add_argument("--seed", type=int, default=42,
                    help="balance-sheet seed (default: 42)")
    args = ap.parse_args()

    results = run_monte_carlo(
        n_replications=args.mc,
        shock_size=args.shock,
        n_banks=args.banks,
        balance_sheet_seed=args.seed,
    )
    summarise(results)


if __name__ == "__main__":
    main()
