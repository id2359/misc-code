"""
Toy stress test with three interacting contagion channels.
Extension of firesale_pykka.py.

Channels:
    (1) FIRE SALES.        Banks below leverage buffer sell common assets;
                           price impact hurts everyone else holding them.
                           (Same as firesale_pykka.py.)

    (2) COUNTERPARTY LOSS. Bilateral interbank loans.  When a bank defaults,
                           its borrowings are written down by (1 - recovery).
                           The lender's asset side takes the haircut, which
                           can push the lender below buffer too.

    (3) FUNDING WITHDRAWAL. A stressed bank's first action (per WP 861
                           pecking order) is to pull its interbank
                           receivables, forcing borrowers to repay from cash
                           or by selling assets (which then triggers (1)).

The three channels feed each other: a default drives (2), which stresses
others, which triggers (3), which triggers (1), which drives further
defaults.  This is the "channel interaction" amplification that BoE WP 861
finds can underestimate systemic risk by up to 5x when modelled in
isolation.

ARCHITECTURE
------------
    Coordinator (orchestrator, not an actor)
        |
        +-- AssetMarket actor       (single shared market)
        +-- LoanBook actor          (registry of all interbank loans)
        +-- Bank actor x N          (one per bank)

Each timestep:

    STEP phase
        - Each bank inspects current prices + its own loan book
        - Produces an ActionPlan: cash to use, funding to pull, assets to sell
        - Pecking order: cash -> pull funding -> fire-sale residual

    ACT phase, sub-step (a): FUNDING PULLS
        - Coordinator routes pull requests through the LoanBook
        - Each borrower receives a "repay this much" message
        - Borrower repays from cash (priority) then queues additional
          fire sales for sub-step (c) if cash insufficient

    ACT phase, sub-step (b): DEFAULTS
        - Banks that are still insolvent default
        - LoanBook writes down all their borrowings at recovery rate R
        - Lenders' balance sheets take the hit

    ACT phase, sub-step (c): FIRE SALES
        - All queued asset sales hit the market simultaneously
        - Prices update via exponential price impact
        - Banks settle at mid-price

    DIAGNOSTICS
        - Record fraction of banks defaulted, by-channel attribution
"""

from __future__ import annotations

import math
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Optional

import pykka


# ---------------------------------------------------------------------------
# Messages
# ---------------------------------------------------------------------------

@dataclass
class GetActionPlan:
    """Step phase: 'what do you want to do this step?'"""
    prices: dict[str, float]
    loan_book_snapshot: dict[str, dict]
    # loan_book_snapshot[bank_id] = {"receivables": [...], "payables": [...]}


@dataclass
class ActionPlan:
    """Bank's reply: a combined plan covering all three channels."""
    bank_id: str
    cash_to_use: float                   # how much cash to spend on debt
    funding_to_pull: list[tuple]         # [(loan_id, amount), ...]
    sell_orders: dict[str, float]        # asset -> qty to sell now
    insolvent: bool


@dataclass
class RepayDemand:
    """Funding pull: borrower must repay `amount` on loan `loan_id`."""
    loan_id: str
    amount: float


@dataclass
class RepayResponse:
    """Borrower replies: how much was actually repaid in cash, how much
    deferred to forced asset sales."""
    bank_id: str
    loan_id: str
    cash_repaid: float
    forced_sales: dict[str, float]
    became_insolvent: bool


@dataclass
class ApplyTrades:
    total_sales: dict[str, float]


@dataclass
class PricesUpdated:
    old_prices: dict[str, float]
    new_prices: dict[str, float]


@dataclass
class WriteDownLoans:
    """LoanBook tells lenders: 'your loan to X is haircut by (1-recovery)'."""
    haircuts: dict[str, float]   # loan_id -> dollars written off the asset


@dataclass
class GetState:
    pass


@dataclass
class Settle:
    """Apply asset trades to balance sheet at mid-price."""
    orders: dict[str, float]
    old_prices: dict[str, float]
    new_prices: dict[str, float]


@dataclass
class AdjustCash:
    """Coordinator moves cash between banks during funding pulls."""
    delta: float   # positive = receive, negative = pay


# ---------------------------------------------------------------------------
# Loan model
# ---------------------------------------------------------------------------

@dataclass
class InterbankLoan:
    """A bilateral interbank loan.  Sits on lender's asset side, borrower's
    liability side.  Both reference the same `loan_id` and `principal`."""
    loan_id: str
    lender: str
    borrower: str
    principal: float


class LoanBook(pykka.ThreadingActor):
    """
    Centralised registry of all interbank loans.  In a real ABM each bank
    would hold its own loan references and they'd be kept in sync via
    contract objects (cf. economicsl's bilateral Contract design).  Here we
    centralise for simplicity — the LoanBook is the single source of truth.
    """

    def __init__(self, loans: list[InterbankLoan]):
        super().__init__()
        self.loans: dict[str, InterbankLoan] = {l.loan_id: l for l in loans}
        self.defaulted_borrowers: set[str] = set()

    def snapshot_for_bank(self, bank_id: str) -> dict:
        recv = [(l.loan_id, l.borrower, l.principal)
                for l in self.loans.values()
                if l.lender == bank_id and l.principal > 0]
        pay = [(l.loan_id, l.lender, l.principal)
               for l in self.loans.values()
               if l.borrower == bank_id and l.principal > 0]
        return {"receivables": recv, "payables": pay}

    def repay(self, loan_id: str, amount: float) -> None:
        """Reduce the principal of a loan by `amount`."""
        loan = self.loans[loan_id]
        loan.principal = max(0.0, loan.principal - amount)

    def write_down_borrowings_of(self, borrower: str, recovery: float
                                 ) -> dict[str, tuple]:
        """When `borrower` defaults, haircut every loan where they're the
        borrower.  Returns {loan_id: (lender, dollars_written_off)} so the
        coordinator can hit each lender's balance sheet."""
        if borrower in self.defaulted_borrowers:
            return {}
        self.defaulted_borrowers.add(borrower)

        haircuts: dict[str, tuple] = {}
        for loan in self.loans.values():
            if loan.borrower == borrower and loan.principal > 0:
                written_off = loan.principal * (1 - recovery)
                haircuts[loan.loan_id] = (loan.lender, written_off)
                loan.principal *= recovery   # recovery value stays as asset
        return haircuts

    def on_receive(self, msg):
        if isinstance(msg, str):
            if msg == "snapshot_all":
                return {bid: self.snapshot_for_bank(bid)
                        for bid in self._all_banks()}
        if isinstance(msg, tuple):
            tag = msg[0]
            if tag == "snapshot":
                return self.snapshot_for_bank(msg[1])
            if tag == "repay":
                _, loan_id, amount = msg
                self.repay(loan_id, amount)
                return None
            if tag == "default":
                _, borrower, recovery = msg
                return self.write_down_borrowings_of(borrower, recovery)

    def _all_banks(self) -> set[str]:
        banks = set()
        for l in self.loans.values():
            banks.add(l.lender)
            banks.add(l.borrower)
        return banks


# ---------------------------------------------------------------------------
# Asset market (unchanged from firesale_pykka.py)
# ---------------------------------------------------------------------------

class AssetMarket(pykka.ThreadingActor):
    PRICE_IMPACT_BENCHMARK = 0.05

    def __init__(self, prices: dict[str, float],
                 market_caps: dict[str, float]):
        super().__init__()
        self.prices = dict(prices)
        self.market_caps = dict(market_caps)
        self.beta = (-math.log(1 - self.PRICE_IMPACT_BENCHMARK)
                     / self.PRICE_IMPACT_BENCHMARK)

    def on_receive(self, msg):
        if isinstance(msg, ApplyTrades):
            old = dict(self.prices)
            for asset, qty in msg.total_sales.items():
                if qty <= 0:
                    continue
                fraction = qty / self.market_caps[asset]
                self.prices[asset] = old[asset] * math.exp(
                    -self.beta * fraction)
            return PricesUpdated(old_prices=old,
                                 new_prices=dict(self.prices))
        if isinstance(msg, str) and msg == "get_prices":
            return dict(self.prices)
        if isinstance(msg, tuple) and msg[0] == "shock":
            _, asset, drop = msg
            self.prices[asset] *= (1 - drop)
            return dict(self.prices)


# ---------------------------------------------------------------------------
# Bank actor
# ---------------------------------------------------------------------------

@dataclass
class Holding:
    asset: str
    quantity: float


class Bank(pykka.ThreadingActor):
    """
    Balance sheet (all par/face except holdings which mark to market):

        Assets:
            cash
            holdings (Tradables)        -- mark-to-market
            interbank receivables       -- par (via LoanBook)
        Liabilities:
            debt (external, e.g. deposits)
            interbank payables          -- par (via LoanBook)

    Equity = total_assets - total_liabilities.
    Leverage = equity / total_assets.

    Pecking order (per WP 861, simplified):
        To delever / repay maturing liabilities:
            1. cash
            2. pull interbank receivables (funding channel)
            3. sell tradables (fire-sale channel)
    """

    LEVERAGE_MIN = 0.03
    LEVERAGE_BUFFER = 0.04
    LEVERAGE_TARGET = 0.05

    # What fraction of interbank receivables can be called per step?
    # Real WP 861 distinguishes by maturity; we use a single haircut.
    FUNDING_RECALLABLE_FRACTION = 1.0

    def __init__(self, bank_id: str, cash: float, holdings: list[Holding],
                 external_debt: float):
        super().__init__()
        self.bank_id = bank_id
        self.cash = cash
        self.holdings = {h.asset: h.quantity for h in holdings}
        self.external_debt = external_debt
        self.insolvent = False

        # Interbank counterparty losses accumulate here as direct
        # writedowns of the cash-equivalent "claims" value (kept as cash
        # for simplicity — in a real model this would be a haircut on the
        # specific receivable contract).
        self.interbank_haircuts_taken = 0.0

    # -- accounting -------------------------------------------------------

    def tradable_value(self, prices: dict[str, float]) -> float:
        return sum(q * prices[a] for a, q in self.holdings.items())

    def receivables_value(self, snapshot: dict) -> float:
        return sum(principal for _, _, principal in snapshot["receivables"])

    def payables_value(self, snapshot: dict) -> float:
        return sum(principal for _, _, principal in snapshot["payables"])

    def total_assets(self, prices: dict[str, float],
                     snapshot: dict) -> float:
        return (self.cash + self.tradable_value(prices)
                + self.receivables_value(snapshot))

    def total_liabilities(self, snapshot: dict) -> float:
        return self.external_debt + self.payables_value(snapshot)

    def equity(self, prices: dict[str, float], snapshot: dict) -> float:
        return self.total_assets(prices, snapshot) - self.total_liabilities(
            snapshot)

    def leverage(self, prices: dict[str, float], snapshot: dict) -> float:
        A = self.total_assets(prices, snapshot)
        if A <= 0:
            return -math.inf
        return self.equity(prices, snapshot) / A

    # -- decision logic ---------------------------------------------------

    def plan(self, prices: dict[str, float], snapshot: dict) -> ActionPlan:
        if self.insolvent:
            return ActionPlan(bank_id=self.bank_id, cash_to_use=0,
                              funding_to_pull=[], sell_orders={},
                              insolvent=True)

        L = self.leverage(prices, snapshot)

        # Hard insolvency: dump everything.
        if L < self.LEVERAGE_MIN:
            self.insolvent = True
            return ActionPlan(
                bank_id=self.bank_id,
                cash_to_use=0,
                funding_to_pull=[(lid, p) for lid, _, p
                                 in snapshot["receivables"]],
                sell_orders=dict(self.holdings),
                insolvent=True,
            )

        # Comfortably above buffer: do nothing.
        if L >= self.LEVERAGE_BUFFER:
            return ActionPlan(bank_id=self.bank_id, cash_to_use=0,
                              funding_to_pull=[], sell_orders={},
                              insolvent=False)

        # Below buffer but solvent: delever via pecking order.
        # Compute dollars of asset reduction needed to hit TARGET.
        E = self.equity(prices, snapshot)
        A = self.total_assets(prices, snapshot)
        A_target = E / self.LEVERAGE_TARGET
        dollars_needed = max(0.0, A - A_target)

        if dollars_needed <= 0:
            return ActionPlan(bank_id=self.bank_id, cash_to_use=0,
                              funding_to_pull=[], sell_orders={},
                              insolvent=False)

        # Step 1: how much can we cover with cash?
        # (Note: using cash to delever means reducing both assets AND
        # liabilities by the same amount; equity unchanged, leverage
        # mechanically improves.)
        cash_use = min(self.cash, dollars_needed)
        remaining = dollars_needed - cash_use

        # Step 2: pull interbank receivables (funding channel).
        funding_to_pull = []
        for lid, _, principal in snapshot["receivables"]:
            if remaining <= 0:
                break
            pull = min(principal * self.FUNDING_RECALLABLE_FRACTION,
                       remaining)
            if pull > 0:
                funding_to_pull.append((lid, pull))
                remaining -= pull

        # Step 3: fire-sale the residual across tradables (proportional).
        sell_orders: dict[str, float] = {}
        if remaining > 0:
            mkt_vals = {a: q * prices[a] for a, q in self.holdings.items()}
            total_mkt = sum(mkt_vals.values())
            if total_mkt > 0:
                for asset, mv in mkt_vals.items():
                    dollars = remaining * (mv / total_mkt)
                    qty = min(dollars / prices[asset], self.holdings[asset])
                    if qty > 0:
                        sell_orders[asset] = qty

        return ActionPlan(bank_id=self.bank_id, cash_to_use=cash_use,
                          funding_to_pull=funding_to_pull,
                          sell_orders=sell_orders, insolvent=False)

    # -- response to being asked to repay (funding channel inbound) -------

    def respond_to_repay_demand(self, loan_id: str, amount: float,
                                prices: dict[str, float],
                                snapshot: dict) -> RepayResponse:
        """Coordinator-called via message: 'You owe `amount` on this loan,
        repay it'.  Borrower pays cash first; if short, queues forced
        asset sales for this step's fire-sale phase."""
        cash_paid = min(self.cash, amount)
        self.cash -= cash_paid
        remaining = amount - cash_paid

        forced_sales: dict[str, float] = {}
        if remaining > 0:
            mkt_vals = {a: q * prices[a] for a, q in self.holdings.items()}
            total_mkt = sum(mkt_vals.values())
            if total_mkt > 0:
                for asset, mv in mkt_vals.items():
                    dollars = remaining * (mv / total_mkt)
                    qty = min(dollars / prices[asset], self.holdings[asset])
                    if qty > 0:
                        forced_sales[asset] = qty
            # If we can't raise enough even by selling everything, we'll
            # tip insolvent in the diagnostic phase.

        return RepayResponse(bank_id=self.bank_id, loan_id=loan_id,
                             cash_repaid=cash_paid,
                             forced_sales=forced_sales,
                             became_insolvent=False)

    # -- message dispatch -------------------------------------------------

    def on_receive(self, msg):
        if isinstance(msg, GetActionPlan):
            snapshot = msg.loan_book_snapshot.get(
                self.bank_id, {"receivables": [], "payables": []})
            return self.plan(msg.prices, snapshot)

        if isinstance(msg, tuple) and msg[0] == "repay_demand":
            _, loan_id, amount, prices, snapshot = msg
            return self.respond_to_repay_demand(loan_id, amount,
                                                prices, snapshot)

        if isinstance(msg, Settle):
            for asset, qty in msg.orders.items():
                mid = 0.5 * (msg.old_prices[asset] + msg.new_prices[asset])
                self.cash += qty * mid
                self.holdings[asset] -= qty
            return None

        if isinstance(msg, AdjustCash):
            self.cash += msg.delta
            return None

        if isinstance(msg, tuple) and msg[0] == "haircut":
            # Counterparty channel: a loan you made got haircut.
            # In this toy model receivables sit in the LoanBook (par value);
            # the writedown lands on this bank as a direct loss recorded
            # against cash (it's actually an asset writedown, but bookkeeping
            # is equivalent at this granularity since equity = A - L).
            _, dollars_written_off = msg
            self.cash -= dollars_written_off
            self.interbank_haircuts_taken += dollars_written_off
            return None

        if isinstance(msg, GetState):
            return {
                "bank_id": self.bank_id,
                "cash": self.cash,
                "holdings": dict(self.holdings),
                "external_debt": self.external_debt,
                "insolvent": self.insolvent,
                "haircuts": self.interbank_haircuts_taken,
            }


# ---------------------------------------------------------------------------
# Coordinator: drives the three-substep act phase
# ---------------------------------------------------------------------------

@dataclass
class StepResult:
    t: int
    prices: dict[str, float]
    leverages: dict[str, float]
    insolvent_now: list[str]
    funding_pulled: float
    counterparty_losses: float
    fire_sale_volume: dict[str, float]


class Coordinator:
    RECOVERY_RATE = 0.40   # 40% recovery on defaulted interbank loans
                           # (typical assumption; WP 861 uses 0% as a stress)

    def __init__(self, market_ref, loanbook_ref, bank_refs: dict):
        self.market = market_ref
        self.loanbook = loanbook_ref
        self.banks = bank_refs
        self.previously_insolvent: set[str] = set()

    def _snapshot_all(self) -> dict:
        return {bid: self.loanbook.ask(("snapshot", bid))
                for bid in self.banks}

    def step(self, t: int) -> StepResult:
        prices = self.market.ask("get_prices")
        snapshots = self._snapshot_all()

        # ----- STEP phase: gather all action plans in parallel -----
        futures = {
            bid: ref.ask(
                GetActionPlan(prices=prices, loan_book_snapshot=snapshots),
                block=False)
            for bid, ref in self.banks.items()
        }
        plans: dict[str, ActionPlan] = {
            bid: fut.get() for bid, fut in futures.items()
        }

        # ----- ACT (a): FUNDING PULLS (counterparty channel triggers) -----
        # For each pull request, ask the borrower to repay.  Cash moves
        # from borrower to puller via the coordinator.  Forced sales (when
        # borrower lacks cash) accumulate into this step's fire-sale book.
        forced_sales: dict[str, dict[str, float]] = defaultdict(
            lambda: defaultdict(float))
        funding_pulled_total = 0.0

        # Build map: loan_id -> (lender, borrower) for routing
        loan_routing = {}
        for bid, snap in snapshots.items():
            for lid, borrower, _ in snap["receivables"]:
                loan_routing[lid] = (bid, borrower)

        for puller_id, plan in plans.items():
            for loan_id, amount in plan.funding_to_pull:
                lender, borrower = loan_routing[loan_id]
                borrower_snap = snapshots[borrower]
                # Send repay demand synchronously (we need the response)
                response: RepayResponse = self.banks[borrower].ask(
                    ("repay_demand", loan_id, amount, prices, borrower_snap)
                )
                # Move cash: borrower -> lender (the cash_repaid amount)
                self.banks[lender].tell(AdjustCash(delta=response.cash_repaid))
                # Update the loan book
                self.loanbook.tell(("repay", loan_id, response.cash_repaid))
                # Queue any forced sales the borrower had to make
                for asset, qty in response.forced_sales.items():
                    forced_sales[borrower][asset] += qty
                funding_pulled_total += response.cash_repaid

        # Re-snapshot after funding pulls (loan principals have changed)
        snapshots = self._snapshot_all()

        # ----- ACT (b): RESOLVE DEFAULTS (counterparty channel writedowns) -
        # A bank is in default this step iff it was insolvent in its plan,
        # or it's now insolvent after funding pulls.  Recompute leverage
        # post-funding-pull to catch new defaults.
        counterparty_losses_total = 0.0
        new_defaults = []
        for bid, plan in plans.items():
            if plan.insolvent and bid not in self.previously_insolvent:
                new_defaults.append(bid)

        # Check for new defaults caused by funding-pull-induced cash drain
        for bid, ref in self.banks.items():
            if bid in self.previously_insolvent or bid in new_defaults:
                continue
            state = ref.ask(GetState())
            A = (state["cash"]
                 + sum(q * prices[a] for a, q in state["holdings"].items())
                 + sum(p for _, _, p in snapshots[bid]["receivables"]))
            L = state["external_debt"] + sum(
                p for _, _, p in snapshots[bid]["payables"])
            if A <= 0 or (A - L) / A < Bank.LEVERAGE_MIN:
                new_defaults.append(bid)

        for defaulter in new_defaults:
            haircuts = self.loanbook.ask(
                ("default", defaulter, self.RECOVERY_RATE))
            for loan_id, (lender, written_off) in haircuts.items():
                self.banks[lender].tell(("haircut", written_off))
                counterparty_losses_total += written_off

        self.previously_insolvent.update(new_defaults)

        # ----- ACT (c): FIRE SALES -----
        # Aggregate planned + forced sales
        aggregate_sales: dict[str, float] = defaultdict(float)
        for plan in plans.values():
            for asset, qty in plan.sell_orders.items():
                aggregate_sales[asset] += qty
        for bid_sales in forced_sales.values():
            for asset, qty in bid_sales.items():
                aggregate_sales[asset] += qty

        update: PricesUpdated = self.market.ask(
            ApplyTrades(total_sales=dict(aggregate_sales)))

        # Settle each bank's sales at mid-price
        for bid, plan in plans.items():
            combined = dict(plan.sell_orders)
            for asset, qty in forced_sales.get(bid, {}).items():
                combined[asset] = combined.get(asset, 0.0) + qty
            if combined:
                self.banks[bid].tell(Settle(orders=combined,
                                            old_prices=update.old_prices,
                                            new_prices=update.new_prices))

        # ----- DIAGNOSTICS -----
        snapshots = self._snapshot_all()
        leverages = {}
        currently_insolvent = []
        for bid, ref in self.banks.items():
            s = ref.ask(GetState())
            snap = snapshots[bid]
            A = (s["cash"]
                 + sum(q * update.new_prices[a]
                       for a, q in s["holdings"].items())
                 + sum(p for _, _, p in snap["receivables"]))
            L_liab = (s["external_debt"]
                      + sum(p for _, _, p in snap["payables"]))
            lev = (A - L_liab) / A if A > 0 else -math.inf
            leverages[bid] = lev
            if s["insolvent"]:
                currently_insolvent.append(bid)

        return StepResult(
            t=t, prices=dict(update.new_prices),
            leverages=leverages, insolvent_now=currently_insolvent,
            funding_pulled=funding_pulled_total,
            counterparty_losses=counterparty_losses_total,
            fire_sale_volume=dict(aggregate_sales),
        )


# ---------------------------------------------------------------------------
# Demo
# ---------------------------------------------------------------------------

def build_system():
    """Five banks with a sparse interbank network.
       Loan graph (lender -> borrower, amount):
           Alpha   -> Beta     100
           Alpha   -> Gamma     80
           Beta    -> Delta    100
           Gamma   -> Delta     60
           Gamma   -> Epsilon   90
           Delta   -> Epsilon   70

       Asset side amounts adjusted so initial leverage matches firesale_pykka.
    """
    initial_prices = {"govies": 1.0, "corporates": 1.0}
    market_caps = {"govies": 200_000.0, "corporates": 200_000.0}

    market = AssetMarket.start(prices=initial_prices,
                               market_caps=market_caps)

    loans = [
        InterbankLoan("L1", "Alpha", "Beta", 100),
        InterbankLoan("L2", "Alpha", "Gamma", 80),
        InterbankLoan("L3", "Beta", "Delta", 100),
        InterbankLoan("L4", "Gamma", "Delta", 60),
        InterbankLoan("L5", "Gamma", "Epsilon", 90),
        InterbankLoan("L6", "Delta", "Epsilon", 70),
    ]
    loanbook = LoanBook.start(loans=loans)

    # Each bank's balance sheet (target ~5% leverage at price=1).
    # Total assets = cash + holdings + interbank_receivables.
    # Total liab = external_debt + interbank_payables.
    # Equity = TA - TL.
    #
    # Receivables / payables per bank (from loan graph above):
    #   Alpha   recv=180  pay=0
    #   Beta    recv=100  pay=100
    #   Gamma   recv=150  pay=80
    #   Delta   recv=70   pay=160
    #   Epsilon recv=0    pay=160
    #
    # Set cash + holdings so total assets = 1000 for all banks (clean):
    #   Alpha:   1000 - 180 = 820 split as cash 50, gov 400, corp 370
    #   Beta:    1000 - 100 = 900 split as cash 30, gov 500, corp 370
    #   Gamma:   1000 - 150 = 850 split as cash 20, gov 300, corp 530
    #   Delta:   1000 - 70  = 930 split as cash 40, gov 600, corp 290
    #   Epsilon: 1000 - 0   = 1000 split as cash 60, gov 200, corp 740
    banks_spec = [
        # id,       cash, gov,  corp, ext_debt   (-> equity check)
        ("Alpha",     50,  400,  370,  950),   # 1000 - (950+0)   = 50  -> 5.0%
        ("Beta",      30,  500,  370,  850),   # 1000 - (850+100) = 50  -> 5.0%
        ("Gamma",     20,  300,  530,  870),   # 1000 - (870+80)  = 50  -> 5.0%
        ("Delta",     40,  600,  290,  795),   # 1000 - (795+160) = 45  -> 4.5%
        ("Epsilon",   60,  200,  740,  800),   # 1000 - (800+160) = 40  -> 4.0%
    ]

    bank_refs = {}
    for bid, cash, gov, corp, ext_debt in banks_spec:
        holdings = [Holding("govies", gov), Holding("corporates", corp)]
        ref = Bank.start(bank_id=bid, cash=cash, holdings=holdings,
                         external_debt=ext_debt)
        bank_refs[bid] = ref

    return market, loanbook, bank_refs


def print_initial_state(market, loanbook, banks):
    prices = market.ask("get_prices")
    print(f"{'='*78}")
    print("Initial state")
    print(f"{'='*78}")
    print(f"  prices: {prices}")
    for bid, ref in banks.items():
        s = ref.ask(GetState())
        snap = loanbook.ask(("snapshot", bid))
        recv = sum(p for _, _, p in snap["receivables"])
        pay = sum(p for _, _, p in snap["payables"])
        A = (s["cash"] + sum(q * prices[a]
                             for a, q in s["holdings"].items()) + recv)
        L = (A - s["external_debt"] - pay) / A
        print(f"  {bid:8s}  cash={s['cash']:5.0f}  "
              f"holdings={sum(s['holdings'].values()):5.0f}  "
              f"recv={recv:4.0f}  pay={pay:4.0f}  "
              f"ext_debt={s['external_debt']:5.0f}  lev={L:6.2%}")


def run_simulation(steps: int = 12, shock_asset: str = "govies",
                   shock_size: float = 0.05):
    market, loanbook, banks = build_system()
    coord = Coordinator(market, loanbook, banks)

    print_initial_state(market, loanbook, banks)

    print(f"\n>>> SHOCK: {shock_asset} writedown of {shock_size:.0%}\n")
    market.ask(("shock", shock_asset, shock_size))

    cumulative_funding = 0.0
    cumulative_counterparty = 0.0
    for t in range(1, steps + 1):
        r = coord.step(t)
        cumulative_funding += r.funding_pulled
        cumulative_counterparty += r.counterparty_losses

        sales = ", ".join(f"{a}={q:.0f}"
                          for a, q in r.fire_sale_volume.items() if q > 0)
        lev = "  ".join(f"{b}={L:6.2%}" for b, L in r.leverages.items())
        prices = ", ".join(f"{a}={p:.4f}" for a, p in r.prices.items())
        new_def = [b for b in r.insolvent_now
                   if b not in (coord.previously_insolvent
                                - set(r.insolvent_now))]

        print(f"t={t}")
        print(f"  prices:           {prices}")
        print(f"  fire-sale vol:    {sales if sales else '(none)'}")
        print(f"  funding pulled:   {r.funding_pulled:7.1f} "
              f"(cum {cumulative_funding:7.1f})")
        print(f"  ctpty losses:     {r.counterparty_losses:7.1f} "
              f"(cum {cumulative_counterparty:7.1f})")
        print(f"  leverages:        {lev}")
        print(f"  insolvent:        {','.join(r.insolvent_now) or '-'}")
        print()

        if (not r.fire_sale_volume
                and r.funding_pulled < 1e-6
                and r.counterparty_losses < 1e-6):
            print(f"(stabilised at t={t})")
            break

    print(f"{'='*78}")
    print("Summary")
    print(f"{'='*78}")
    print(f"  Total funding pulled:      {cumulative_funding:.1f}")
    print(f"  Total counterparty losses: {cumulative_counterparty:.1f}")
    print(f"  Final insolvent banks:     "
          f"{sorted(coord.previously_insolvent)}")
    print(f"  Final default rate:        "
          f"{len(coord.previously_insolvent)}/{len(banks)} "
          f"= {len(coord.previously_insolvent)/len(banks):.0%}")

    market.stop()
    loanbook.stop()
    for ref in banks.values():
        ref.stop()


if __name__ == "__main__":
    run_simulation(steps=12, shock_asset="govies", shock_size=0.05)
