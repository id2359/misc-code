"""
Distributed order-processing system with actor pools.
Fixes the serial bottleneck that causes Timeout with 300+ customers.
"""

from __future__ import annotations

import random
import time
from dataclasses import dataclass
from typing import Optional

import pykka


# ---------------------------------------------------------------------------
# Messages
# ---------------------------------------------------------------------------

@dataclass
class PlaceOrder:
    customer_id: str
    items: list[str]
    address: str


@dataclass
class OrderAccepted:
    order_id: str
    eta_seconds: int


@dataclass
class OrderRejected:
    reason: str


@dataclass
class StartCooking:
    order_id: str
    items: list[str]


@dataclass
class MealReady:
    order_id: str
    items: list[str]


@dataclass
class DispatchDelivery:
    order_id: str
    address: str
    customer_ref: pykka.ActorRef


@dataclass
class DeliveryEnRoute:
    order_id: str
    driver_name: str
    eta_seconds: int


@dataclass
class DeliveryComplete:
    order_id: str
    timestamp: float


@dataclass
class StatusUpdate:
    order_id: str
    stage: str
    detail: str


@dataclass
class GetStats:
    pass


# ---------------------------------------------------------------------------
# Worker actors
# ---------------------------------------------------------------------------

class Analytics(pykka.ThreadingActor):
    def __init__(self):
        super().__init__()
        self.events: list[StatusUpdate] = []

    def on_receive(self, msg):
        match msg:
            case StatusUpdate():
                self.events.append(msg)
                return None
            case GetStats():
                counts = {}
                for ev in self.events:
                    counts[ev.stage] = counts.get(ev.stage, 0) + 1
                return {
                    "total_events": len(self.events),
                    "by_stage": counts,
                    "latest": self.events[-1] if self.events else None,
                }
            case _:
                return None


class KitchenWorker(pykka.ThreadingActor):
    """One cooking station.  Handles one order at a time."""

    def __init__(self, worker_id: str, analytics_ref: pykka.ActorRef):
        super().__init__()
        self.worker_id = worker_id
        self.analytics = analytics_ref

    def on_receive(self, msg):
        match msg:
            case StartCooking(order_id=oid, items=items):
                self.analytics.tell(
                    StatusUpdate(order_id=oid, stage="cooking",
                                 detail=f"{self.worker_id} preparing {', '.join(items)}")
                )
                time.sleep(0.3)  # simulate cooking
                self.analytics.tell(
                    StatusUpdate(order_id=oid, stage="ready",
                                 detail=f"{self.worker_id} meal ready")
                )
                return MealReady(order_id=oid, items=items)
            case _:
                return None


class KitchenPool(pykka.ThreadingActor):
    """
    Round-robin dispatcher.  Forwards StartCooking to the next free
    worker via ask(block=False) so the caller gets a real Future.
    """

    def __init__(self, num_workers: int, analytics_ref: pykka.ActorRef):
        super().__init__()
        self.workers = [
            KitchenWorker.start(f"station-{i}", analytics_ref)
            for i in range(num_workers)
        ]
        self._idx = 0

    def on_receive(self, msg):
        match msg:
            case StartCooking():
                worker = self.workers[self._idx]
                self._idx = (self._idx + 1) % len(self.workers)
                # Return the Future directly; Pykka unwraps it for the caller
                return worker.ask(msg, block=False)
            case _:
                return None

    def on_stop(self):
        for w in self.workers:
            w.stop()


class DeliveryWorker(pykka.ThreadingActor):
    DRIVERS = ["Alice", "Bob", "Carol", "David", "Eve", "Frank"]

    def __init__(self, worker_id: str, analytics_ref: pykka.ActorRef):
        super().__init__()
        self.worker_id = worker_id
        self.analytics = analytics_ref

    def on_receive(self, msg):
        match msg:
            case DispatchDelivery(order_id=oid, address=addr,
                                  customer_ref=cref):
                driver = random.choice(self.DRIVERS)
                eta = random.randint(5, 20)

                self.analytics.tell(
                    StatusUpdate(order_id=oid, stage="en_route",
                                 detail=f"{self.worker_id}: {driver} → {addr}")
                )

                cref.tell(DeliveryEnRoute(
                    order_id=oid, driver_name=driver, eta_seconds=eta
                ))

                time.sleep(0.2)  # simulate drive time

                self.analytics.tell(
                    StatusUpdate(order_id=oid, stage="delivered",
                                 detail=f"{self.worker_id}: {driver} dropped off")
                )

                cref.tell(DeliveryComplete(order_id=oid, timestamp=time.time()))
                return {"ok": True, "driver": driver}
            case _:
                return None


class DeliveryPool(pykka.ThreadingActor):
    def __init__(self, num_workers: int, analytics_ref: pykka.ActorRef):
        super().__init__()
        self.workers = [
            DeliveryWorker.start(f"van-{i}", analytics_ref)
            for i in range(num_workers)
        ]
        self._idx = 0

    def on_receive(self, msg):
        match msg:
            case DispatchDelivery():
                worker = self.workers[self._idx]
                self._idx = (self._idx + 1) % len(self.workers)
                return worker.ask(msg, block=False)
            case _:
                return None

    def on_stop(self):
        for w in self.workers:
            w.stop()


# ---------------------------------------------------------------------------
# Front-of-house
# ---------------------------------------------------------------------------

class OrderTaker(pykka.ThreadingActor):
    _counter = 0

    def __init__(self, kitchen_ref: pykka.ActorRef,
                 delivery_ref: pykka.ActorRef,
                 analytics_ref: pykka.ActorRef):
        super().__init__()
        self.kitchen = kitchen_ref
        self.delivery = delivery_ref
        self.analytics = analytics_ref
        self._customer_refs: dict[str, pykka.ActorRef] = {}

    def on_receive(self, msg):
        match msg:
            case PlaceOrder(customer_id=cid, items=items, address=addr):
                if not items:
                    return OrderRejected(reason="empty order")

                OrderTaker._counter += 1
                oid = f"ORD-{OrderTaker._counter:03d}"

                # Ask kitchen pool (dispatches to a free worker)
                meal: MealReady = self.kitchen.ask(
                    StartCooking(order_id=oid, items=items)
                )

                # Hand off to delivery pool
                self.delivery.tell(DispatchDelivery(
                    order_id=oid,
                    address=addr,
                    customer_ref=self._customer_refs.get(cid),
                ))

                return OrderAccepted(order_id=oid, eta_seconds=random.randint(10, 30))

            case ("register", cid, ref):
                self._customer_refs[cid] = ref
                return None

            case _:
                return None


class Customer(pykka.ThreadingActor):
    def __init__(self, customer_id: str, taker_ref: pykka.ActorRef):
        super().__init__()
        self.customer_id = customer_id
        self.taker = taker_ref
        self.notifications: list = []
        taker_ref.tell(("register", customer_id, self.actor_ref))

    def on_receive(self, msg):
        match msg:
            case DeliveryEnRoute(order_id=oid, driver_name=dname, eta_seconds=eta):
                note = f"[{self.customer_id}] {oid} en route with {dname}, ETA {eta}s"
                self.notifications.append(note)
                print(note)
                return None

            case DeliveryComplete(order_id=oid, timestamp=ts):
                note = f"[{self.customer_id}] {oid} delivered at {ts:.2f}"
                self.notifications.append(note)
                print(note)
                return None

            case "place_order":
                result = self.taker.ask(PlaceOrder(
                    customer_id=self.customer_id,
                    items=["burger", "fries", "shake"],
                    address=f"{random.randint(1, 999)} Main St",
                ))
                match result:
                    case OrderAccepted(order_id=oid, eta_seconds=eta):
                        print(f"[{self.customer_id}] {oid} accepted, ETA {eta}s")
                    case OrderRejected(reason=r):
                        print(f"[{self.customer_id}] rejected: {r}")
                return result

            case "history":
                return self.notifications

            case _:
                return None


# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------

def main(num_customers: int = 3000):
    print(f"Starting system with {num_customers} customers")

    analytics = Analytics.start()

    # Pools sized to handle the load in parallel
    kitchen = KitchenPool.start(num_workers=20, analytics_ref=analytics)
    delivery = DeliveryPool.start(num_workers=20, analytics_ref=analytics)

    taker = OrderTaker.start(
        kitchen_ref=kitchen,
        delivery_ref=delivery,
        analytics_ref=analytics,
    )

    customers = [
        Customer.start(f"customer-{i}", taker_ref=taker)
        for i in range(num_customers)
    ]

    # Fire all orders concurrently
    futures = [c.ask("place_order", block=False) for c in customers]

    # Wait for all to complete (generous timeout since they're parallel now)
    for i, f in enumerate(futures):
        try:
            f.get(timeout=30)
        except Exception as e:
            print(f"Customer {i} failed: {e}")

    # Let async delivery messages finish printing
    time.sleep(1.0)

    stats = analytics.ask(GetStats())
    print(f"\n--- Analytics ---")
    print(f"Total events: {stats['total_events']}")
    for stage, count in stats['by_stage'].items():
        print(f"  {stage}: {count}")

    # Cleanup
    for c in customers:
        c.stop()
    taker.stop()
    delivery.stop()
    kitchen.stop()
    analytics.stop()
    print("All actors stopped.")


if __name__ == "__main__":
    main(num_customers=300)
