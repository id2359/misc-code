# Fire-Sale Stress Testing in Pykka: Three Implementations

This document explains three progressively richer Python implementations of agent-based fire-sale stress testing, all built on the [Pykka](https://www.pykka.org/) actor framework. They are pedagogical reimplementations of the methodology in the Oxford-INET stress-testing programme (Aymanns, Farmer, Kleinnijenhuis, Wetzer and collaborators), culminating in Bank of England Staff Working Paper No. 861 (Farmer, Kleinnijenhuis, Nahai-Williamson & Wetzer 2020).

The three files form a teaching sequence:

| File | LOC | Banks | Channels | Purpose |
|---|---|---|---|---|
| `firesale_pykka.py` | ~430 | 5 | Fire sales only | Pure fire-sale contagion via Pykka actors |
| `firesale2.py` | ~600 | 5 | Fire sales + funding + counterparty | Three interacting channels |
| `firesale3.py` | ~430 | 48 (configurable) | All three | EBA-scale, Hałaj–Kok networks, Monte Carlo |

Each file is self-contained and runnable. `firesale3.py` imports the actor classes from `firesale2.py` without modification — the actor design scales unchanged from 5 to 48 banks.

## Table of Contents

1. [Background: What These Models Do](#background-what-these-models-do)
2. [Common Architecture](#common-architecture)
3. [`firesale_pykka.py`: Fire Sales Only](#firesale_pykkapy-fire-sales-only)
4. [`firesale2.py`: Three Channels](#firesale2py-three-channels)
5. [`firesale3.py`: EBA Scale with Monte Carlo](#firesale3py-eba-scale-with-monte-carlo)
6. [Comparing the Implementations](#comparing-the-implementations)
7. [Limitations and Departures from the Original](#limitations-and-departures-from-the-original)
8. [References and Further Reading](#references-and-further-reading)

---

## Background: What These Models Do

System-wide stress testing simulates how a shock to one or more banks propagates through the financial system via multiple **contagion channels**, producing endogenous amplification of the initial loss. The intellectual claim — central to the Oxford-INET research programme — is that traditional microprudential stress tests, which model banks one at a time, miss this amplification entirely and can therefore underestimate systemic risk by factors of 3–5×.

The three channels modelled here are:

1. **Fire sales of common assets.** Banks share asset holdings. A stressed bank sells assets to delever; the sale pushes prices down; falling prices mark down everyone else's holdings; those banks may then have to sell too. This is *indirect* contagion via overlapping portfolios — no bilateral relationship needed.

2. **Counterparty losses on bilateral exposures.** Banks lend to each other. When one defaults, its borrowings are written down; the lenders take a direct hit to their asset side. This is *direct* contagion via interbank exposures.

3. **Funding withdrawal.** When a bank is stressed but not yet insolvent, it may pull short-term funding it has extended to others. The borrowers must repay — either from cash or by selling assets, feeding back into channel (1).

Each channel in isolation can be modelled with a fairly simple framework. The Oxford research argues — and these implementations demonstrate at toy scale — that the *interaction* of channels is qualitatively different: a small loss in one channel can trigger a cascade that crosses channels and amplifies far beyond what any single channel would predict.

### Theoretical lineage

The fire-sale mechanism traces back to Shleifer & Vishny (1992) on asset specificity and forced sales, was formalised in a financial-stability context by Cifuentes, Ferrucci & Shin (2005), and was extended into agent-based stress-testing form by Cont & Schaanning (2017) and Greenwood, Landier & Thesmar (2015). The leverage-targeting behavioural rule comes from Adrian & Shin (2010, 2014). The multi-channel architecture, eigenvalue stability analysis, and the systematic study of channel interaction are the contributions of the Oxford-INET group: Aymanns, Farmer, Kleinnijenhuis & Wetzer (2018) is the canonical handbook chapter; Farmer, Kleinnijenhuis, Nahai-Williamson & Wetzer (2020) is the Bank of England working paper that operationalises it on the full EBA 2018 sample; Wiersema, Kleinnijenhuis, Wetzer & Farmer (2023) gives the closed-form eigenvalue stability criterion.

---

## Common Architecture

All three implementations share the same conceptual ontology, inherited from the Oxford-INET `economicsl` library:

- **Agents** are entities with a balance sheet (cash, holdings, debt).
- **Contracts** are bilateral relationships (loans, asset positions) that appear simultaneously on two agents' balance sheets.
- **Markets** are price-formation venues.
- **Actions** are deferred state changes: agents emit `Action` objects rather than mutating each other directly.
- **Two-phase commit** per timestep: in the *step phase* every agent decides what to do given the current state; in the *act phase* all actions execute simultaneously. This eliminates artificial sequencing effects where the agent that goes first benefits at others' expense.

In `economicsl` (the Oxford library) the two-phase commit is enforced by a flag (`SIMULTANEOUS_FIRESALE = True`) that separates `step()` (queue actions) from `act()` (apply queued actions) within a single-threaded simulation kernel. Pykka gives us the same pattern with actual concurrency: actors run on separate threads, the coordinator collects their decisions via the `ask` pattern (blocking on a future), then dispatches the aggregated update.

### The Pykka mapping

| `economicsl` concept | Pykka mapping in these files |
|---|---|
| `Agent` | `pykka.ThreadingActor` subclass with balance-sheet state |
| `Contract` | A dataclass (e.g., `Holding`, `InterbankLoan`) referenced by both parties |
| `Market` | An `AssetMarket` actor holding shared price state |
| `Action` (queued) | A message sent via `ref.tell(...)` or `ref.ask(...)` |
| Step phase | Coordinator broadcasts `GetSellOrders` / `GetActionPlan` via `ask(block=False)`, gathers futures |
| Act phase | Coordinator sends aggregated trades to market, then settlement to banks |

A subtle but important property: Pykka actors process their inboxes serially on their own threads. The coordinator's parallel `ask(...)` to all banks lets each bank decide concurrently against the same snapshot, but settlement is funnelled back through the coordinator. This matches the design intent of `economicsl`'s simultaneous-fire-sale mode: concurrent decision, synchronous settlement.

---

## `firesale_pykka.py`: Fire Sales Only

### Purpose

The minimal viable implementation: one contagion channel (fire sales), no interbank network, no funding withdrawal. Demonstrates the actor pattern, the leverage-targeting behaviour, and the exponential price-impact dynamics.

### Architecture

```
Coordinator (orchestrator)
    |
    +-- AssetMarket actor       (single shared market)
    +-- Bank actor x N          (5 banks, holding overlapping assets)
```

Messages: `GetSellOrders`, `SellOrders`, `ApplyTrades`, `PricesUpdated`, `Settle`, `GetState`.

### Per-timestep loop

```
STEP phase:
  Coordinator.ask(bank, GetSellOrders(prices), block=False) for each bank
  Collect SellOrders futures
  Aggregate sell volumes by asset

ACT phase:
  Coordinator.ask(market, ApplyTrades(total_sales))
  Market updates prices via exponential impact, returns PricesUpdated
  Coordinator.tell(bank, Settle(...)) for each bank with non-empty orders

DIAGNOSTICS:
  Coordinator.ask(bank, GetState()) for each bank
  Compute leverage, identify newly insolvent banks
```

### Key parameters

| Parameter | Value | Source |
|---|---|---|
| `LEVERAGE_MIN` | 3% | Basel III leverage ratio minimum |
| `LEVERAGE_BUFFER` | 4% | Deleveraging trigger |
| `LEVERAGE_TARGET` | 5% | Restore-to level |
| `PRICE_IMPACT_BENCHMARK` | 5% sold ⇒ 5% drop | Standard calibration (Cont-Schaanning 2017) |
| Asset universe | govies, corporates | Two-asset simplification |
| Market caps | 200,000 each | Sized so banks are small fraction of market |

The exponential price impact uses the Cifuentes-Ferrucci-Shin form:

```python
beta = -math.log(1 - 0.05) / 0.05    # ≈ 1.0259
new_price = old_price * math.exp(-beta * fraction_sold)
```

Sales settle at the **mid-price** between pre- and post-impact prices — this is the WP 861 convention and neither rewards nor penalises the trader for the impact of their own sale.

### Behavioural rule (`Bank.decide_sales`)

When a bank's leverage L drops below the buffer:
- If L < MIN: declare insolvent, dump all holdings (forced liquidation).
- If L ≥ BUFFER: do nothing.
- Otherwise: compute dollars-to-sell to restore TARGET, allocate proportionally across holdings by current market value.

The leverage-targeting maths:

> If equity = E and current assets = A, the bank wants to reach assets A* such that E/A* = TARGET. So A* = E/TARGET, and the amount to sell is max(0, A − A*).

This formula assumes a bank repays liabilities with the sale proceeds (not retaining cash), so equity stays constant while assets shrink — exactly the deleveraging story.

### What you observe

With a 5% shock to govies on a 5-bank system (the included demo):

- **t=1**: Direct shock drops govies to 0.95. Mean leverage across banks falls from ~5% to ~2.5%. Beta and Delta (4.5%–4% starting leverage) breach the 3% minimum and dump everything.
- **t=2**: Those forced sales push govies and corporates further down. The remaining banks tip below 3% from the contagion alone. All five insolvent.
- **t=3**: System stabilised. 3 of the 5 defaults are pure contagion — they happened because of *other* banks' fire sales, not the initial shock.

That's the BoE WP 861 finding in miniature: amplification through shared exposures.

### Why this is a toy

Beyond what's modelled, the simplifications are:
- No interbank exposures (no contagion via direct loans).
- No funding withdrawals (the only response to stress is fire sales).
- No bail-in or resolution mechanism.
- Asset-class agnostic pecking order (proportional liquidation rather than least-price-impact-first).
- Only leverage ratio binds (no RWA, no LCR).

---

## `firesale2.py`: Three Channels

### Purpose

Adds the two missing contagion channels — counterparty losses and funding withdrawal — to show how channel interactions amplify systemic risk beyond what fire sales alone produce.

### Architecture

```
Coordinator (orchestrator)
    |
    +-- AssetMarket actor       (single shared market)
    +-- LoanBook actor          (registry of all interbank loans)
    +-- Bank actor x N          (5 banks with bilateral interbank network)
```

New actor: `LoanBook` — a centralised registry of bilateral loans. Each `InterbankLoan` has a lender, borrower, and principal. The LoanBook is the single source of truth; banks query it for snapshots of their receivables and payables when computing balance sheets.

This is a pragmatic simplification of `economicsl`'s bilateral-Contract design (where the contract object lives on both parties' balance sheets simultaneously). Centralising the registry trades a bit of theoretical elegance for substantially simpler bookkeeping. The algebra is unchanged: a loan still appears as an asset to the lender and a liability to the borrower; the LoanBook just owns the canonical state.

### Per-timestep loop

The two-phase commit becomes a **step phase + three-substep act phase**:

```
STEP phase:
  Coordinator.ask(bank, GetActionPlan(prices, loan_snapshots), block=False)
  Each bank produces an ActionPlan with three components:
    cash_to_use:      dollars of cash to spend on debt
    funding_to_pull:  list of (loan_id, amount) to call in
    sell_orders:      asset -> qty to sell now

ACT phase (a): FUNDING PULLS
  For each pull request, send RepayDemand to borrower
  Borrower repays from cash; if short, queues forced sales for substep (c)
  Cash moves: borrower -> lender (via AdjustCash messages)
  LoanBook updates principals

ACT phase (b): DEFAULT RESOLUTION
  Identify newly insolvent banks (insolvent at plan time + tipped post-funding)
  For each defaulter, LoanBook.write_down_borrowings_of(borrower, recovery)
  Each lender receives ("haircut", written_off) — equity loss

ACT phase (c): FIRE SALES
  Aggregate planned + forced sales
  Market.ApplyTrades(total_sales) -> new prices
  Each bank settles its (planned + forced) sales at mid-price
```

### The pecking order

The key behavioural addition is in `Bank.plan()`: when a bank is below buffer but solvent, it pursues a **WP 861-style pecking order**:

1. **Use cash first.** Reducing cash and debt by the same amount mechanically improves leverage without selling anything.
2. **Pull interbank receivables.** This is the funding channel — the bank calls in short-term loans it has extended.
3. **Fire-sale residual.** Only what's left after cash and funding pulls becomes asset sales.

The order matters because the channels have different externalities. Cash use is invisible to everyone else. Pulling funding moves cash between banks but doesn't move asset prices — gentler externality. Fire sales move prices, which hits every bank holding that asset. The pecking order corresponds to the *increasing* externality severity of each option — the standard private-cost-first rule.

### Counterparty losses

When a bank defaults, its borrowings are written down at a recovery rate (default 40%; the WP 861 stress scenario uses 0%). The LoanBook reduces every loan where the defaulter is the borrower:

```python
loan.principal *= recovery     # the recovery part stays as an asset
haircuts[loan_id] = (lender, written_off)   # the non-recovery part is the lender's loss
```

Each lender then receives a haircut message, which reduces their cash (bookkeeping shorthand for an asset writedown). Their leverage drops, possibly triggering their own deleveraging next step.

### What you observe

The shock-size sweep (`sweep.py`) shows three regimes:

| Shock | Fire-only defaults | Multi-channel defaults | Mechanism |
|---|---|---|---|
| 1% | 0/5 | 0/5 (but 70 funding pulled) | Funding as shock absorber: cash recall avoids any sales |
| 2% | 1/5 | 0/5 | Funding *prevents* a default that fire sales would have caused |
| 3% | 3/5 | 4/5 | Counterparty losses tip a marginal bank that fire sales spared |
| ≥4% | 5/5 | 5/5 | Both models cascade fully |

The 2% case is interesting: a model with *more* channels has *fewer* defaults because the pecking order substitutes a low-externality response (funding pull) for a high-externality one (fire sale). The 3% case shows the opposite: counterparty losses provide an additional contagion path that fire sales alone don't cover.

At larger scale (`firesale3.py`), the same dynamics produce the headline WP 861 finding: ignoring channel interactions can underestimate systemic risk substantially.

### Recovery rate sensitivity

The `Coordinator.RECOVERY_RATE = 0.40` constant is the single biggest knob in this file. Setting it to 0.0 gives the WP 861 worst-case stress assumption — every defaulter wipes out 100% of its lenders' claims. Setting it to 1.0 disables the counterparty channel entirely. Real-world calibration depends on jurisdiction, seniority, and collateral; the LGD literature (Schuermann 2004, Frye 2000) is the standard reference.

---

## `firesale3.py`: EBA Scale with Monte Carlo

### Purpose

Demonstrates that the actor design from `firesale2.py` scales from 5 to 48 banks without modification, and adds two pieces of methodology that are essential for using these models in practice: bilateral network reconstruction (because the true bilateral data is confidential) and Monte Carlo over network realisations.

### What's new

The actor classes are imported unchanged from `firesale2.py`. Three pieces of new code:

1. **`generate_eba_sample(n_banks=48, seed=42)`** — synthesises a heterogeneous EU-SIB-like sample.
2. **`reconstruct_network_halaj_kok(specs, max_bilateral_frac=0.20, seed=…)`** — the Hałaj–Kok algorithm.
3. **Monte Carlo driver** — `run_monte_carlo(n_replications, …)` and `summarise(results)`.

### Synthetic balance sheets

For each of 48 banks, the generator produces:

| Field | Distribution | Range |
|---|---|---|
| `total_assets` | log-normal | 50–2000 (bn) |
| `leverage_ratio` | 0.035 + 0.035 × Beta(2,5) | 3.5–7%, mean ~4.5% |
| `govies_share` of tradables | U(0.25, 0.75) | sovereign exposure varies |
| `cash_share` of assets | U(0.05, 0.12) | 5–12% |
| `interbank_recv_share` | U(0.04, 0.12) | 4–12% |
| `interbank_pay_share` | U(0.04, 0.12) → scaled | balanced with recv at system level |

The leverage distribution is the most important calibration choice. Beta(2,5) on [0,1] has mean 2/7 ≈ 0.286, so mapping it to [3.5%, 7%] gives mean ~4.5% with most banks clustered between 4% and 5.5%. This puts a meaningful fraction of the system within striking distance of the 3% minimum — which is what makes the cascade possible. With a more relaxed distribution (mean 6%, say) the system absorbs shocks easily and there's no interesting dynamic.

The system-level interbank receivables and payables are explicitly balanced (`scale = total_recv / total_pay`) because any bilateral matrix must satisfy this conservation constraint.

### Hałaj–Kok network reconstruction

When you know each bank's *aggregate* interbank receivables (A_i) and payables (D_j) — which is publicly reported — but not the bilateral matrix L_ij — which is supervisory confidential — you need to reconstruct a plausible bilateral structure. The Hałaj–Kok algorithm (Hałaj & Kok 2013, ECB Working Paper 1506) is the standard technique:

> Iteratively pick random (i, j) pairs with remaining row and column capacity, draw L_ij ∼ U(0, 20% × min(remaining)), accumulate, decrement remainders. Stop when row and column residuals are exhausted.

Why this and not, say, maximum entropy (Upper & Worms 2004)? Maximum entropy produces a fully-connected dense network that systematically *underestimates* systemic risk — it spreads exposures so evenly that no single counterparty matters. Hałaj–Kok produces sparse, heterogeneous networks that match the empirically observed core-periphery structure of real interbank networks better (Craig & von Peter 2014).

The implementation has a few practical wrinkles:

- A self-loop guard (`L_ii = 0`) — banks don't lend to themselves.
- A "stuck row" fallback: if the only column with remaining capacity is the same row, distribute the residual proportionally to other columns. This rarely fires but prevents the algorithm from looping forever.
- A residual cleanup at the end: any small (<0.1% of total) residual is pro-rated.
- A threshold (0.5 currency units) below which entries are dropped — keeps the loan list tidy.

With ~9% interbank share and 48 banks, you typically get 200–400 non-zero bilateral loans per realisation. That's the right order of magnitude empirically: the FR Y-15 interbank exposure data for US G-SIBs shows a similar density.

### Monte Carlo driver

The driver fixes the balance sheets (one seed) and varies only the network seed across replications. This matches the Oxford methodology: average over network *uncertainty*, not balance-sheet uncertainty. The balance sheets are taken as given (they come from supervisory data); only the bilateral structure is unknown.

```python
def run_monte_carlo(n_replications, shock_size, n_banks=48, balance_sheet_seed=42):
    specs = generate_eba_sample(n_banks, seed=balance_sheet_seed)
    results = []
    for rep in range(n_replications):
        r = run_one_replication(specs, "govies", shock_size,
                                network_seed=1000 + rep)
        results.append(r)
    return results
```

Output reports mean, sd, min, max across replications for default count, default rate, final asset prices, fire-sale volume, funding pulled, counterparty losses, simulation length, plus the Gai-Kapadia systemic event rate (≥5% of banks defaulted).

### What you observe

At default parameters (48 banks, mean leverage 4.44%, 100 replications):

| Shock | Mean defaults | Sd | Min | Max |
|---|---|---|---|---|
| 1% | 0.0 | 0.0 | 0 | 0 |
| 2% | 38.6 | 4.4 | 24 | 43 |
| 3% | 45.2 | 0.5 | 45 | 47 |
| 5% | 46.3 | 2.1 | 44 | 48 |

The 2% shock is the interesting case. Between 1% (nothing happens) and 3% (~94% cascade) there is a sharp threshold, and at the threshold the network realisation determines the outcome. The standard deviation of 4.4 banks (~9% of the system) is the *uncertainty introduced by not knowing the bilateral network*. A single point estimate would be 10–20 banks off the mean in either direction. That's exactly why the Oxford team runs N=100 replications: not for statistical noise reduction, but to quantify the irreducible network uncertainty.

### Performance

On a modest laptop: ~2 replications per second, ~50 seconds for 100 reps. Each replication spawns 50 actors (48 banks + market + loanbook), runs 15–20 timesteps with three message rounds per step, then tears down. Pykka's thread-per-actor model is the bottleneck — most time is in thread creation/destruction and message-passing overhead, not the actual computation.

For production work the natural optimisations are:
- **Parallelise replications.** Each replication is independent. `multiprocessing.Pool` would give near-linear speedup.
- **Vectorise off Pykka.** The Oxford code is single-threaded NumPy-vectorised over banks for exactly this reason. You lose the actor-model elegance but gain 10–100× throughput. The reference implementation in `economicsl` is in this style.
- **Batch the Monte Carlo.** Reuse balance sheets and asset market across replications, only rebuilding the loan book.

### CLI

```bash
python firesale3.py                                # defaults: 48 banks, 20 reps, 5% shock
python firesale3.py --shock 0.02 --mc 100          # full WP 861-style run
python firesale3.py --banks 100 --shock 0.03       # larger system
python firesale3.py --seed 7 --shock 0.05          # different balance sheet realisation
```

---

## Comparing the Implementations

### Scale and complexity

| | `firesale_pykka.py` | `firesale2.py` | `firesale3.py` |
|---|---|---|---|
| Lines of code | ~430 | ~600 | ~430 (+ imports) |
| Bank actors | 5 | 5 | 48 (configurable) |
| Asset universe | 2 | 2 | 2 |
| Channels modelled | 1 (fire sales) | 3 | 3 |
| Network reconstruction | n/a | hand-specified | Hałaj–Kok |
| Monte Carlo | no | no | yes |
| Runtime per simulation | ~0.05s | ~0.1s | ~0.5s × N reps |

### Architectural progression

Each file adds capability while reusing the previous level's abstractions:

- `firesale_pykka.py` establishes the **two-phase commit** pattern via Pykka actors and the **leverage-targeting + price-impact** behavioural mechanics.
- `firesale2.py` adds the **LoanBook actor** and refactors the act phase into **three substeps** (funding pulls → defaults → fire sales). The `Bank` actor's `plan()` method produces a *combined* action plan rather than just sell orders.
- `firesale3.py` adds **data generation** (`generate_eba_sample`) and **network reconstruction** (`reconstruct_network_halaj_kok`) on top, plus the **Monte Carlo driver**. The actor classes from `firesale2.py` are imported unchanged.

That last point is the test of whether the actor abstraction was right: scaling 10× in bank count and adding a Monte Carlo wrapper required *zero changes* to the inner loop. The actor model handles it.

### Key dependencies

```
firesale_pykka.py:  pykka
firesale2.py:       pykka
firesale3.py:       pykka, numpy, firesale2.py
sweep.py:           none (subprocess calls)
compare.py:         none (subprocess calls)
```

---

## Limitations and Departures from the Original

For honest disclosure, here is what these implementations *don't* do that the full BoE WP 861 framework does:

### Missing channels and mechanisms

1. **No bail-in waterfall.** Defaulted banks just dump assets. There's no CET1 → AT1 → T2 → senior bail-in cascade, no 8% TLOF rule, no SRF/SRB. Adding this is the subject of Farmer, Goodhart & Kleinnijenhuis (2021) and would substantially enrich the resolution dynamics.
2. **No LCR or RWA constraints.** Only the Basel III leverage ratio binds. WP 861 finds the leverage ratio binds most often empirically, but the model includes all three constraints with their distinct pecking orders.
3. **No derivatives, no repos.** All "interbank loans" are unsecured term loans. Real interbank funding markets are dominated by repo with collateral haircuts.
4. **Single recovery rate.** A flat 40% applied to all defaulted exposures. Real LGDs depend on seniority, collateral, jurisdiction, and recovery time.
5. **No maturity structure on interbank loans.** All loans are 100% recallable on demand. Real funding markets have a maturity profile; only the short-tenor portion is callable per period.

### Simplifications in the model architecture

1. **Centralised `LoanBook`** rather than bilateral contract objects. Equivalent in algebra; loses the directional information about which counterparty bled you.
2. **Counterparty haircuts hit cash** rather than the specific receivable contract. Bookkeeping-equivalent at this granularity but loses the contract-level audit trail.
3. **Proportional liquidation** rather than least-price-impact-first. WP 861's pecking order is asset-class-specific.
4. **`apply_shock` pokes market state** rather than sending a structured `Shock` message. Minor inelegance.
5. **No investment funds or hedge funds.** WP 861 models 42 banks + 4 representative investment funds + representative hedge funds. These play distinct roles in the contagion (funds typically face redemption-driven sales, hedge funds have higher leverage).

### Data simplifications

1. **Synthetic balance sheets** rather than real EBA 2018 data. The structure is faithful but the exact numbers are not.
2. **Two-asset universe** (govies + corporates) rather than the granular Basel risk-weight categories.
3. **Single asset market** rather than separate markets per asset class with cross-asset price impact correlations.

### What the toy *does* faithfully reproduce

Despite these simplifications, the three implementations capture the **qualitative findings** of WP 861:
- Multi-channel models produce richer dynamics than single-channel.
- Channel interactions can produce defaults that no single channel would produce alone.
- Network structure matters: the variance across Monte Carlo replications is large at the threshold.
- The pecking order matters: rearranging the order of responses to stress changes outcomes.
- Buffer "usability" matters: how aggressively banks defend their thresholds determines how readily they dump assets.

For pedagogical purposes — building intuition about how these models work, learning the actor pattern, or experimenting with new behavioural rules — these implementations are sufficient. For policy analysis on real banking systems, use the original `ox-inet-resilience/resilience` codebase.

---

## References and Further Reading

### Primary Oxford-INET stress-testing papers

- **Aymanns, C., Farmer, J. D., Kleinnijenhuis, A. M., & Wetzer, T. (2018).** "Models of Financial Stability and Their Application in Stress Tests." Forthcoming as Ch. 6 of the *Handbook of Computational Economics* Vol. 4 (LeBaron & Hommes, eds.); University of St. Gallen Research Paper 2018/5; SSRN 3022752; INET Oxford WP 2018-06. *The canonical handbook chapter introducing the multiplex framework.*

- **Farmer, J. D., Kleinnijenhuis, A. M., Nahai-Williamson, P., & Wetzer, T. (2020).** "Foundations of System-Wide Financial Stress Testing with Heterogeneous Institutions." Bank of England Staff Working Paper No. 861, May 2020 (also INET Oxford WP 2020-14, SSRN 3601846). *The main reference. Operationalises the framework on the full EBA 2018 sample with all five blocks (Institutions, Contracts, Markets, Constraints, Behaviour).*

- **Wiersema, G., Kleinnijenhuis, A. M., Wetzer, T., & Farmer, J. D. (2023).** "Scenario-Free Analysis of Financial Stability with Interacting Contagion Channels." *Journal of Banking & Finance* 146:106684. *The eigenvalue stability criterion — gives a closed-form, scenario-free instability threshold ν > 1 calibratable from aggregate balance-sheet shares.*

- **Farmer, J. D., Goodhart, C. A. E., & Kleinnijenhuis, A. M. (2021).** "Systemic Implications of the Bail-In Design." CEPR DP 16509; INET Oxford WP 2021-21; SUERF Policy Note 257; LSE Research Online 111903. *Extends the multiplex framework with the BRRD bail-in waterfall as a fifth contagion channel.*

- **Farmer, J. D., Kleinnijenhuis, A. M., Schuermann, T., & Wetzer, T. (eds., 2022).** *Handbook of Financial Stress Testing.* Cambridge University Press. *Comprehensive reference with chapters from regulators, practitioners, and academics. Foreword by Timothy Geithner; endorsements by Ben Bernanke and Christine Lagarde.*

- **Kemp, E., Kleinnijenhuis, A. M., Wetzer, T., & Wiersema, G. (2021).** "Higher-Order Exposures." Working paper using granular South-African Reserve Bank data. *Decomposes total exposures into direct + indirect (overlapping portfolios) + higher-order (spill-over) components.*

### Foundational papers on individual mechanisms

#### Fire sales and price impact

- **Shleifer, A., & Vishny, R. W. (1992).** "Liquidation Values and Debt Capacity: A Market Equilibrium Approach." *Journal of Finance* 47(4): 1343–1366. *The original asset-specificity argument: distressed sales happen at fire-sale prices because the natural buyers are also distressed.*

- **Cifuentes, R., Ferrucci, G., & Shin, H. S. (2005).** "Liquidity Risk and Contagion." *Journal of the European Economic Association* 3(2-3): 556–566. *First formal model of fire-sale contagion via mark-to-market accounting. The exponential price-impact form used in these implementations comes from this paper.*

- **Greenwood, R., Landier, A., & Thesmar, D. (2015).** "Vulnerable Banks." *Journal of Financial Economics* 115(3): 471–485. *Introduces the leverage-targeting + linear price impact framework used in the BoE WP 861 implementation. Provides empirical calibration for European banks.*

- **Cont, R., & Schaanning, E. (2017).** "Fire Sales, Indirect Contagion and Systemic Stress Testing." Working paper; published 2019 in *Mathematics and Financial Economics*. *The methodology that the public `ox-inet-resilience/firesale_stresstest` repo is explicitly described as reproducing.*

- **Cont, R., & Schaanning, E. (2019).** "Monitoring Indirect Contagion." *Journal of Banking & Finance* 104: 85–102. *Operationalises the framework for regulatory monitoring.*

#### Leverage targeting and procyclicality

- **Adrian, T., & Shin, H. S. (2010).** "Liquidity and Leverage." *Journal of Financial Intermediation* 19(3): 418–437. *The empirical demonstration that broker-dealers target leverage ratios. Foundation for the behavioural rule used throughout this literature.*

- **Adrian, T., & Shin, H. S. (2014).** "Procyclical Leverage and Value-at-Risk." *Review of Financial Studies* 27(2): 373–403. *Theoretical mechanism linking VaR-based risk management to leverage targeting.*

#### Counterparty contagion and interbank networks

- **Allen, F., & Gale, D. (2000).** "Financial Contagion." *Journal of Political Economy* 108(1): 1–33. *The seminal paper on contagion via interbank claims. Shows that network structure matters: complete networks are more resilient than incomplete ones in their model.*

- **Eisenberg, L., & Noe, T. H. (2001).** "Systemic Risk in Financial Systems." *Management Science* 47(2): 236–249. *The fixed-point algorithm for clearing payments in a network of mutually exposed firms. Foundational to all subsequent network-contagion work.*

- **Upper, C., & Worms, A. (2004).** "Estimating Bilateral Exposures in the German Interbank Market: Is There a Danger of Contagion?" *European Economic Review* 48(4): 827–849. *The maximum-entropy approach to network reconstruction. Important contrast to Hałaj–Kok.*

- **Hałaj, G., & Kok, C. (2013).** "Assessing Interbank Contagion Using Simulated Networks." ECB Working Paper No. 1506. *The Hałaj–Kok algorithm used in `firesale3.py`. Iterative random pair-matching produces more realistic sparse networks than maximum entropy.*

- **Craig, B., & von Peter, G. (2014).** "Interbank Tiering and Money Center Banks." *Journal of Financial Intermediation* 23(3): 322–347. *Empirically documents the core-periphery structure of interbank networks.*

- **Gai, P., & Kapadia, S. (2010).** "Contagion in Financial Networks." *Proceedings of the Royal Society A* 466(2120): 2401–2423. *Network-theoretic analysis of cascade dynamics. The 5%-of-banks "systemic event" threshold used in WP 861 and `firesale3.py` comes from this paper.*

- **Acemoglu, D., Ozdaglar, A., & Tahbaz-Salehi, A. (2015).** "Systemic Risk and Stability in Financial Networks." *American Economic Review* 105(2): 564–608. *Theoretical analysis: small shocks favour dense networks; large shocks favour sparse ones. Phase-transition flavour.*

#### Loss given default

- **Schuermann, T. (2004).** "What Do We Know About Loss Given Default?" Federal Reserve Bank of Philadelphia. *The reference survey on LGD estimation and calibration.*

- **Frye, J. (2000).** "Depressing Recoveries." *Risk Magazine* November. *Correlation between default rates and recovery rates in stress.*

### Climate finance work by Kleinnijenhuis (not directly relevant to these implementations but worth knowing)

- **Adrian, T., Bolton, P., & Kleinnijenhuis, A. M. (2022).** "The Great Carbon Arbitrage." IMF Working Paper 2022/107; CEPR DP 17569. *Estimates ~$85tn net social benefit from coordinated coal phase-out. Profiled by Gillian Tett in the FT.*

- **Baer, M., Caldecott, B., Kastl, J., Kleinnijenhuis, A. M., & Ranger, N. (2022).** "TRISK — A Climate Stress Test for Transition Risk." SSRN 4254114. *Asset-level transition-risk stress test for power, oil & gas, coal, and automotive sectors.*

- **Bolton, P., Edenhofer, O., Kleinnijenhuis, A. M., Rockström, J., & Zettelmeyer, J. (2025).** "Why coalitions of wealthy nations should fund others to decarbonize." *Nature* 639(8055): 574–576. *Latest Bruegel/Nature follow-up on climate finance architecture.*

### Regulatory and policy context

- **Basel Committee on Banking Supervision (2017).** "Basel III: Finalising post-crisis reforms." *The regulatory framework for the capital, leverage, and liquidity ratios modelled in WP 861.*

- **Financial Stability Board (2014).** "Adequacy of loss-absorbing capacity of global systemically important banks in resolution." *Total Loss Absorbing Capacity (TLAC) standard. Foundational for Farmer-Goodhart-Kleinnijenhuis 2021.*

- **European Banking Authority (2018).** "2018 EU-Wide Stress Test Results." *The 48-bank sample used by `ox-inet-resilience/firesale_stresstest`.*

- **Bank of England (2018-present).** "System-Wide Exploratory Scenario" exercises. *The regulatory practice of system-wide stress testing that WP 861 informs.*

### Software and code

- **`ox-inet-resilience/firesale_stresstest`** (GitHub). *Apache-2.0; the public fire-sale-only implementation in Python, ~150 lines per module. Reproduces Cont-Schaanning 2017 on EBA 2018 data.* https://github.com/ox-inet-resilience/firesale_stresstest

- **`ox-inet-resilience/resilience`** and **`ox-inet-resilience/sw_stresstest`** (GitHub). *The full multi-channel implementation, built on the team's `economicsl` library. Apache-2.0.*

- **`INET-Complexity/economicsl`** (GitHub). *The agent-based simulation framework underneath. Provides Agent, Contract, Action, and Simulation primitives. Original is Scala; a partial Python port (`py-economicsl`) is the one used by the stress-test repos.*

- **Pykka** documentation. *The actor framework used in these implementations.* https://www.pykka.org/

### Surveys and review pieces

- **Bardoscia, M., Barucca, P., Battiston, S., Caccioli, F., Cimini, G., Garlaschelli, D., Saracco, F., Squartini, T., & Caldarelli, G. (2021).** "The Physics of Financial Networks." *Nature Reviews Physics* 3: 490–507. *Comprehensive review of network methods in finance.*

- **Battiston, S., Caldarelli, G., May, R. M., Roukny, T., & Stiglitz, J. E. (2016).** "The price of complexity in financial networks." *Proceedings of the National Academy of Sciences* 113(36): 10031–10036. *Argues that complex network structures can amplify rather than dampen systemic risk.*

- **Glasserman, P., & Young, H. P. (2016).** "Contagion in Financial Networks." *Journal of Economic Literature* 54(3): 779–831. *Standard survey of network-contagion theory.*

### Pedagogical / introductory

- **Haldane, A. G. (2009).** "Rethinking the financial network." Speech at the Financial Student Association, Amsterdam, April 2009. *Highly readable introduction to the network view of financial stability; framed the post-crisis regulatory agenda.*

- **Bookstaber, R. (2017).** *The End of Theory: Financial Crises, the Failure of Economics, and the Sweep of Human Interaction.* Princeton University Press. *Non-technical but conceptually deep treatment of agent-based models in finance by an Office of Financial Research veteran.*

- **Farmer, J. D. (2024).** *Making Sense of Chaos: A Better Economics for a Better World.* Yale University Press / Allen Lane. *Recent popular book by the lead architect of this research programme. Chapter on financial stability is particularly relevant.*

### People to follow

- **J. Doyne Farmer** (Oxford / Santa Fe Institute): the intellectual lead of the Oxford-INET programme. Personal site has talks and papers.
- **Alissa M. Kleinnijenhuis** (Cornell / Imperial / Columbia): personal site at https://www.alissakleinnijenhuis.com/. The CEPR VoxTalks Climate Finance podcast.
- **Thom Wetzer** (Oxford): runs the Oxford Sustainable Law Programme; the legal/regulatory voice in the team.
- **Garbrand Wiersema** (ECB / INET): co-author of the eigenvalue stability paper.
- **Stefano Battiston** (University of Zurich): independent network-contagion programme, often complementary findings.
- **Rama Cont** (Oxford): the other major Oxford voice in this area; runs the OMI (Oxford-Man Institute).

### Conferences and venues

- **Federal Reserve Stress Testing Research Conference** (Boston Fed, annual)
- **Bank of England / RAMP / RiskLab annual macroprudential conferences**
- **ESRB / ECB Macroprudential Conference** (biennial)
- **NBER Risks of Financial Institutions** programme meetings
- **Office of Financial Research annual conference**
- **CEPR ESSIM** (European Summer Symposium in International Macroeconomics)
- **ICLR / NeurIPS** workshops on AI for finance (where the Evology / market-ecology work appears)
