"""
Toy fire-sale stress test using Pykka actors.

Architecture mirrors the Oxford-INET `economicsl`/firesale_stresstest design:

    Coordinator (kernel)
        |
        +-- AssetMarket actor       (single shared market, holds prices)
        +-- Bank actor x N          (one per bank, holds balance sheet)

Per timestep, the Coordinator runs a two-phase commit:

    STEP phase:  ask every bank "given current prices, how much do you want
                 to sell of each asset?"  Banks reply with sell orders.
                 Nothing executes yet.

    ACT phase:   send aggregated sell volumes to the market in one shot.
                 Market updates prices via the exponential price-impact
                 function and replies with the new price vector.
                 Coordinator broadcasts new prices to all banks.

This is the simultaneous-firesale pattern: every bank sees the same price
snapshot when deciding, and prices update once per step.  Sequencing
artifacts (whoever-acts-first gets the best price) are eliminated.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import pykka


# ---------------------------------------------------------------------------
# Messages (plain dataclasses — Pykka actors handle any picklable object)
# ---------------------------------------------------------------------------

@dataclass
class GetSellOrders:
    """Step phase: 'tell me what you want to sell at current prices'."""
    prices: dict[str, float]


@dataclass
class SellOrders:
    """Bank's reply: quantity of each asset it wants to offload."""
    bank_id: str
    orders: dict[str, float]   # asset_name -> quantity to sell
    insolvent: bool


@dataclass
class ApplyTrades:
    """Act phase: aggregated sell volumes hit the market."""
    total_sales: dict[str, float]   # asset_name -> total quantity sold


@dataclass
class PricesUpdated:
    """Market broadcasts new prices; banks mark-to-market."""
    old_prices: dict[str, float]
    new_prices: dict[str, float]


@dataclass
class GetState:
    """Diagnostic: ask a bank for its current state."""
    pass


# ---------------------------------------------------------------------------
# AssetMarket actor
# ---------------------------------------------------------------------------

class AssetMarket(pykka.ThreadingActor):
    """
    Holds prices for a set of assets.  Applies exponential price impact:

        p_new = p_old * exp(-beta * q_sold / market_cap)

    with beta calibrated so that selling 5% of market cap drops the price
    by 5%:  beta = -ln(1 - 0.05) / 0.05  ≈  1.0259.
    """

    PRICE_IMPACT_BENCHMARK = 0.05   # 5% sold -> 5% drop

    def __init__(self, prices: dict[str, float], market_caps: dict[str, float]):
        super().__init__()
        self.prices = dict(prices)
        self.market_caps = dict(market_caps)
        self.beta = -math.log(1 - self.PRICE_IMPACT_BENCHMARK) / self.PRICE_IMPACT_BENCHMARK

    def on_receive(self, msg):
        if isinstance(msg, ApplyTrades):
            old = dict(self.prices)
            for asset, qty in msg.total_sales.items():
                if qty <= 0:
                    continue
                cap = self.market_caps[asset]
                fraction = qty / cap
                self.prices[asset] = old[asset] * math.exp(-self.beta * fraction)
            return PricesUpdated(old_prices=old, new_prices=dict(self.prices))
        if isinstance(msg, str) and msg == "get_prices":
            return dict(self.prices)


# ---------------------------------------------------------------------------
# Bank actor
# ---------------------------------------------------------------------------

@dataclass
class Holding:
    """A position in a tradable asset.  Quantity in units, valued at market."""
    asset: str
    quantity: float


class Bank(pykka.ThreadingActor):
    """
    A bank with:
      - holdings (list of Holding) on the asset side, valued mark-to-market
      - cash on the asset side (par value, unaffected by market)
      - debt on the liability side (par value)
      - equity = assets - debt
      - leverage = equity / assets

    Behaviour: leverage-targeting.  Three thresholds:
        LEVERAGE_MIN     (3%)  -> insolvent below this, exits
        LEVERAGE_BUFFER  (4%)  -> trigger deleveraging below this
        LEVERAGE_TARGET  (5%)  -> deleverage back to this level

    Sales are proportional across asset holdings (pecking order: simplest case).
    """

    LEVERAGE_MIN = 0.03
    LEVERAGE_BUFFER = 0.04
    LEVERAGE_TARGET = 0.05

    def __init__(self, bank_id: str, cash: float, holdings: list[Holding],
                 debt: float):
        super().__init__()
        self.bank_id = bank_id
        self.cash = cash
        self.holdings = {h.asset: h.quantity for h in holdings}
        self.debt = debt
        self.insolvent = False

    # -- accounting -------------------------------------------------------

    def total_assets(self, prices: dict[str, float]) -> float:
        mkt_value = sum(q * prices[a] for a, q in self.holdings.items())
        return self.cash + mkt_value

    def equity(self, prices: dict[str, float]) -> float:
        return self.total_assets(prices) - self.debt

    def leverage(self, prices: dict[str, float]) -> float:
        A = self.total_assets(prices)
        if A <= 0:
            return -math.inf
        return self.equity(prices) / A

    # -- behaviour --------------------------------------------------------

    def decide_sales(self, prices: dict[str, float]) -> dict[str, float]:
        """
        Compute proportional sell orders to restore leverage to TARGET.

        If current leverage L < BUFFER, the bank needs to shrink the balance
        sheet.  Let E = equity, A = current assets, A* = E / TARGET.
        Amount to delever (in dollars of market-value assets to sell):
            delta = A - A*
        Then proportionally allocate across holdings by current value.
        """
        if self.insolvent:
            return {}

        L = self.leverage(prices)
        if L < self.LEVERAGE_MIN:
            self.insolvent = True
            # On insolvency, dump everything (a simplification — in WP 861
            # there's a contagion-free resolution option, but for a toy
            # model this captures the "forced liquidation" worst case).
            return dict(self.holdings)

        if L >= self.LEVERAGE_BUFFER:
            return {}   # no action needed

        E = self.equity(prices)
        A = self.total_assets(prices)
        A_target = E / self.LEVERAGE_TARGET
        delta_dollars = A - A_target
        if delta_dollars <= 0:
            return {}

        # Proportional liquidation across holdings (by current market value).
        mkt_values = {a: q * prices[a] for a, q in self.holdings.items()}
        total_mkt = sum(mkt_values.values())
        if total_mkt <= 0:
            return {}

        orders: dict[str, float] = {}
        for asset, mkt_val in mkt_values.items():
            dollars_to_sell = delta_dollars * (mkt_val / total_mkt)
            qty_to_sell = min(dollars_to_sell / prices[asset],
                              self.holdings[asset])
            if qty_to_sell > 0:
                orders[asset] = qty_to_sell
        return orders

    def settle_sales(self, orders: dict[str, float],
                     old_prices: dict[str, float],
                     new_prices: dict[str, float]) -> None:
        """
        Apply the trades to the balance sheet.  Sales settle at the
        mid-price between pre- and post-impact prices (the WP 861
        convention — neither too generous nor too punitive).
        """
        for asset, qty in orders.items():
            mid_price = 0.5 * (old_prices[asset] + new_prices[asset])
            proceeds = qty * mid_price
            self.holdings[asset] -= qty
            self.cash += proceeds

    # -- message dispatch -------------------------------------------------

    def on_receive(self, msg):
        if isinstance(msg, GetSellOrders):
            orders = self.decide_sales(msg.prices)
            return SellOrders(bank_id=self.bank_id, orders=orders,
                              insolvent=self.insolvent)
        if isinstance(msg, PricesUpdated):
            # We need to know what *this* bank sold to settle proceeds.
            # In a fully decoupled design the coordinator would pass back
            # only this bank's allocation; here we re-derive from old prices.
            # For simplicity, the coordinator sends settlement separately.
            return None
        if isinstance(msg, tuple) and msg[0] == "settle":
            _, orders, old_prices, new_prices = msg
            self.settle_sales(orders, old_prices, new_prices)
            return None
        if isinstance(msg, GetState):
            return {
                "bank_id": self.bank_id,
                "cash": self.cash,
                "holdings": dict(self.holdings),
                "debt": self.debt,
                "insolvent": self.insolvent,
            }


# ---------------------------------------------------------------------------
# Coordinator: the kernel that runs the two-phase loop
# ---------------------------------------------------------------------------

@dataclass
class StepResult:
    t: int
    prices: dict[str, float]
    leverages: dict[str, float]
    insolvent: list[str]
    total_sales: dict[str, float]


class Coordinator:
    """
    Not an actor itself — just the orchestrator.  Drives the step/act
    cycle by ask-pattern messages (which block until the actor replies),
    so we get deterministic synchronisation without writing our own
    barrier.  Pykka's `.ask()` is synchronous; `.tell()` is fire-and-forget.
    """

    def __init__(self, market_ref, bank_refs):
        self.market = market_ref
        self.banks = bank_refs   # dict[bank_id, ActorRef]

    def step(self, t: int) -> StepResult:
        prices = self.market.ask("get_prices")

        # ----- STEP phase: ask everyone in parallel, gather replies -----
        futures = {
            bid: ref.ask(GetSellOrders(prices=prices), block=False)
            for bid, ref in self.banks.items()
        }
        replies: dict[str, SellOrders] = {
            bid: fut.get() for bid, fut in futures.items()
        }

        # ----- Aggregate sell orders -----
        total_sales: dict[str, float] = {a: 0.0 for a in prices}
        for r in replies.values():
            for asset, qty in r.orders.items():
                total_sales[asset] += qty

        # ----- ACT phase: market clears, prices update -----
        update: PricesUpdated = self.market.ask(
            ApplyTrades(total_sales=total_sales)
        )

        # ----- Settle each bank's trades at mid-price -----
        for bid, r in replies.items():
            if r.orders:
                self.banks[bid].tell(
                    ("settle", r.orders, update.old_prices, update.new_prices)
                )

        # ----- Diagnostics -----
        states = {bid: ref.ask(GetState()) for bid, ref in self.banks.items()}
        leverages = {}
        insolvent = []
        for bid, s in states.items():
            A = s["cash"] + sum(q * update.new_prices[a]
                                for a, q in s["holdings"].items())
            E = A - s["debt"]
            L = E / A if A > 0 else -math.inf
            leverages[bid] = L
            if s["insolvent"]:
                insolvent.append(bid)

        return StepResult(
            t=t,
            prices=dict(update.new_prices),
            leverages=leverages,
            insolvent=insolvent,
            total_sales=total_sales,
        )


# ---------------------------------------------------------------------------
# Demo: run a small system, apply a shock, watch contagion
# ---------------------------------------------------------------------------

def build_system():
    """Five banks, two assets, overlapping holdings.  Mirrors the spirit
    of the EBA 2018 sample but with toy numbers for legibility."""

    initial_prices = {"govies": 1.0, "corporates": 1.0}
    market_caps = {"govies": 200_000.0, "corporates": 200_000.0}

    market = AssetMarket.start(prices=initial_prices, market_caps=market_caps)

    # Each bank has a different leverage profile and asset mix.
    # Equity = (cash + holdings_mkt_value) - debt.  At leverage ~5%, a bank
    # with $1000 assets has $50 equity and $950 debt.
    banks_spec = [
        # (id,    cash, govies, corporates, debt)   -> equity at price=1
        ("Alpha",   50,    400,    550,        950),   # 50 / 1000 = 5%
        ("Beta",    30,    600,    370,        950),   # 50 / 1000 = 5%
        ("Gamma",   20,    300,    680,        950),   # 50 / 1000 = 5%
        ("Delta",   40,    700,    260,        955),   # 45 / 1000 = 4.5%
        ("Epsilon", 60,    200,    740,        960),   # 40 / 1000 = 4%, fragile
    ]

    bank_refs = {}
    for bid, cash, gov, corp, debt in banks_spec:
        holdings = [Holding("govies", gov), Holding("corporates", corp)]
        ref = Bank.start(bank_id=bid, cash=cash, holdings=holdings, debt=debt)
        bank_refs[bid] = ref

    return market, bank_refs


def apply_shock(market_ref, asset: str, drop: float):
    """Exogenous initial shock: writedown an asset price by `drop`."""
    prices = market_ref.ask("get_prices")
    prices[asset] *= (1 - drop)
    # Manually update the market actor's state.  In a real model this
    # would arrive as a structured Shock message.
    market_ref.proxy().prices = prices
    return prices


def run_simulation(steps: int = 8, shock_asset: str = "govies",
                   shock_size: float = 0.20):
    market, banks = build_system()
    coord = Coordinator(market, banks)

    print(f"{'='*72}")
    print(f"Initial state")
    print(f"{'='*72}")
    initial_prices = market.ask("get_prices")
    print(f"  prices: {initial_prices}")
    for bid, ref in banks.items():
        s = ref.ask(GetState())
        A = s["cash"] + sum(q * initial_prices[a]
                            for a, q in s["holdings"].items())
        L = (A - s["debt"]) / A
        print(f"  {bid:8s}  assets={A:7.1f}  debt={s['debt']:6.1f}  "
              f"leverage={L:6.2%}")

    print(f"\n>>> SHOCK: {shock_asset} writedown of {shock_size:.0%}\n")
    apply_shock(market, shock_asset, shock_size)

    results = []
    for t in range(1, steps + 1):
        r = coord.step(t)
        results.append(r)
        sales_str = ", ".join(f"{a}={q:.1f}" for a, q in r.total_sales.items()
                              if q > 0)
        lev_str = "  ".join(f"{bid}={L:6.2%}" for bid, L in r.leverages.items())
        price_str = ", ".join(f"{a}={p:.4f}" for a, p in r.prices.items())
        insolv_str = ",".join(r.insolvent) if r.insolvent else "-"
        print(f"t={t}  prices: {price_str}")
        print(f"      sales:  {sales_str if sales_str else '(none)'}")
        print(f"      lev:    {lev_str}")
        print(f"      insolvent: {insolv_str}\n")

        # Stop early if system has stabilised
        if all(q < 1e-6 for q in r.total_sales.values()):
            print(f"(stabilised at t={t})")
            break

    # Cleanup
    market.stop()
    for ref in banks.values():
        ref.stop()

    return results


if __name__ == "__main__":
    # A 5% govies writedown: not enough to fail anyone outright, but
    # Epsilon (4% leverage) breaches its buffer immediately and starts
    # to delever.  Its sales push prices down a touch more, dragging
    # Delta (4.5%) below buffer too.  And so on.
    run_simulation(steps=12, shock_asset="govies", shock_size=0.05)
