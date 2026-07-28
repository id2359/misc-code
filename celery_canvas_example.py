#!/usr/bin/env python3
"""
Small Celery canvas demo showing:

- simple tasks
- chain
- group
- chord
- map / starmap
- chunks

Run a worker in another shell:
    celery -A celery_canvas_example worker --loglevel=info

Then run this script:
    python celery_canvas_example.py

This example uses Redis by default. Override with:
    export CELERY_BROKER_URL=redis://localhost:6379/0
    export CELERY_RESULT_BACKEND=redis://localhost:6379/0
"""

from __future__ import annotations

import os
from time import sleep

from celery import Celery, chain, chord, group


BROKER_URL = os.getenv("CELERY_BROKER_URL", "redis://localhost:6379")
print(BROKER_URL)
RESULT_BACKEND = os.getenv("CELERY_RESULT_BACKEND", BROKER_URL)
print(RESULT_BACKEND)

app = Celery("canvas_example", broker=BROKER_URL, backend=RESULT_BACKEND)
print(app.conf)



@app.task
def add(x: int, y: int) -> int:
    sleep(0.2)
    return x + y


@app.task
def mul(x: int, y: int) -> int:
    sleep(0.2)
    return x * y


@app.task
def square(x: int) -> int:
    sleep(0.2)
    return x * x


@app.task
def tsum(values: list[int]) -> int:
    return sum(values)


@app.task
def describe(value) -> str:
    return f"Result: {value!r}"


@app.task
def collect(*values):
    return list(values)


def demo_chain() -> None:
    workflow = chain(add.s(2, 3), square.s(), describe.s())
    result = workflow.delay()
    print("chain ->", result.get(timeout=200))


def demo_group() -> None:
    jobs = group(square.s(i) for i in range(6))
    result = jobs.delay()
    print("group ->", result.get(timeout=20))


def demo_chord() -> None:
    header = group(add.s(i, i + 1) for i in range(5))
    body = tsum.s()
    result = chord(header)(body)
    print("chord ->", result.get(timeout=20))


def demo_chain_with_group() -> None:
    workflow = chain(
        group(add.s(i, 10) for i in range(4)),
        tsum.s(),
        mul.s(3),
        describe.s(),
    )
    result = workflow.delay()
    print("chain(group(...)) ->", result.get(timeout=20))


def demo_map_starmap() -> None:
    map_result = add.map([(1, 2), (3, 4), (5, 6)]).delay()
    starmap_result = add.starmap([(10, 20), (30, 40)]).delay()
    print("map ->", map_result.get(timeout=20))
    print("starmap ->", starmap_result.get(timeout=20))


def demo_chunks() -> None:
    result = add.chunks([(i, i + 100) for i in range(8)], 3).delay()
    print("chunks ->", result.get(timeout=20))


def demo_nested_canvas() -> None:
    workflow = chord(
        [
            chain(add.s(1, 2), square.s()),
            chain(add.s(3, 4), square.s()),
            chain(add.s(5, 6), square.s()),
        ]
    )(tsum.s())
    print("nested canvas ->", workflow.get(timeout=20))

