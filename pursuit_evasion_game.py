#!/usr/bin/env python3
"""
pursuit_evasion_game.py

Approximate differential game of pursuit and evasion.

State dynamics:
    xdot_P = v_P [cos(theta_P), sin(theta_P)]
    xdot_E = v_E [cos(theta_E), sin(theta_E)]

The pursuer chooses a heading to minimize separation.
The evader chooses a heading to maximize separation.

At each step we solve a small local minimax game over a finite set
of candidate headings. This is not a full Hamilton-Jacobi-Isaacs PDE
solver, but it gives a useful computational introduction to
pursuit-evasion differential games.

Requirements:
    pip install numpy matplotlib

Run:
    python3 pursuit_evasion_game.py

Optional:
    python3 pursuit_evasion_game.py --save pursuit.png
"""

import argparse
import math
import numpy as np
import matplotlib.pyplot as plt


def unit_from_angle(theta):
    return np.array([math.cos(theta), math.sin(theta)], dtype=float)


def distance(a, b):
    return float(np.linalg.norm(a - b))


def minimax_headings(
    pursuer_pos,
    evader_pos,
    pursuer_speed,
    evader_speed,
    dt,
    lookahead_steps=8,
    n_headings=72,
):
    """
    Approximate a zero-sum local differential game.

    payoff = predicted future separation

    Pursuer minimizes the worst-case payoff.
    Evader maximizes the payoff.
    """
    angles = np.linspace(0.0, 2.0 * math.pi, n_headings, endpoint=False)
    horizon = dt * lookahead_steps

    payoff = np.empty((n_headings, n_headings), dtype=float)

    for i, theta_p in enumerate(angles):
        p_future = pursuer_pos + pursuer_speed * horizon * unit_from_angle(theta_p)

        for j, theta_e in enumerate(angles):
            e_future = evader_pos + evader_speed * horizon * unit_from_angle(theta_e)
            payoff[i, j] = distance(p_future, e_future)

    # For each pursuer action, assume the evader makes the best response.
    worst_case = payoff.max(axis=1)

    # Pursuer selects action with smallest worst-case separation.
    i_star = int(np.argmin(worst_case))

    # Evader selects best response to the chosen pursuer action.
    j_star = int(np.argmax(payoff[i_star]))

    return angles[i_star], angles[j_star], payoff[i_star, j_star]


def simulate(
    pursuer_start=(0.0, 0.0),
    evader_start=(8.0, 5.0),
    pursuer_speed=1.5,
    evader_speed=1.0,
    dt=0.05,
    max_time=30.0,
    capture_radius=0.25,
    lookahead_steps=8,
    n_headings=72,
):
    pursuer = np.array(pursuer_start, dtype=float)
    evader = np.array(evader_start, dtype=float)

    pursuer_track = [pursuer.copy()]
    evader_track = [evader.copy()]
    distances = [distance(pursuer, evader)]
    times = [0.0]

    t = 0.0
    captured = False

    while t < max_time:
        if distance(pursuer, evader) <= capture_radius:
            captured = True
            break

        theta_p, theta_e, _ = minimax_headings(
            pursuer,
            evader,
            pursuer_speed,
            evader_speed,
            dt,
            lookahead_steps=lookahead_steps,
            n_headings=n_headings,
        )

        pursuer += pursuer_speed * dt * unit_from_angle(theta_p)
        evader += evader_speed * dt * unit_from_angle(theta_e)

        t += dt

        pursuer_track.append(pursuer.copy())
        evader_track.append(evader.copy())
        distances.append(distance(pursuer, evader))
        times.append(t)

    return {
        "captured": captured,
        "time": t,
        "pursuer_track": np.array(pursuer_track),
        "evader_track": np.array(evader_track),
        "distances": np.array(distances),
        "times": np.array(times),
    }


def plot_result(result, capture_radius, save=None):
    p = result["pursuer_track"]
    e = result["evader_track"]

    fig, ax = plt.subplots(figsize=(9, 7))
    ax.plot(p[:, 0], p[:, 1], label="Pursuer")
    ax.plot(e[:, 0], e[:, 1], label="Evader")

    ax.scatter(p[0, 0], p[0, 1], marker="o", s=80, label="Pursuer start")
    ax.scatter(e[0, 0], e[0, 1], marker="s", s=80, label="Evader start")
    ax.scatter(p[-1, 0], p[-1, 1], marker="x", s=100)
    ax.scatter(e[-1, 0], e[-1, 1], marker="x", s=100)

    circle = plt.Circle(p[-1], capture_radius, fill=False, linestyle="--")
    ax.add_patch(circle)

    status = (
        f"Capture at t = {result['time']:.2f}"
        if result["captured"]
        else f"No capture by t = {result['time']:.2f}"
    )

    ax.set_xlabel("x")
    ax.set_ylabel("y")
    ax.set_title("Pursuit-Evasion Differential Game\n" + status)
    ax.axis("equal")
    ax.grid(True)
    ax.legend()

    if save:
        fig.savefig(save, dpi=150, bbox_inches="tight")
        print(f"Saved trajectory plot to {save}")
    else:
        plt.show()


def plot_distance(result):
    fig, ax = plt.subplots(figsize=(9, 5))
    ax.plot(result["times"], result["distances"])
    ax.set_xlabel("time")
    ax.set_ylabel("separation")
    ax.set_title("Pursuer-Evader Separation")
    ax.grid(True)
    plt.show()


def main():
    parser = argparse.ArgumentParser(
        description="Approximate minimax pursuit-evasion differential game."
    )
    parser.add_argument("--pursuer-speed", type=float, default=1.5)
    parser.add_argument("--evader-speed", type=float, default=1.0)
    parser.add_argument("--capture-radius", type=float, default=0.25)
    parser.add_argument("--max-time", type=float, default=30.0)
    parser.add_argument("--dt", type=float, default=0.05)
    parser.add_argument("--headings", type=int, default=72)
    parser.add_argument("--lookahead", type=int, default=8)
    parser.add_argument("--save", type=str, default=None)
    args = parser.parse_args()

    if args.pursuer_speed <= 0 or args.evader_speed <= 0:
        raise SystemExit("Speeds must be positive.")

    result = simulate(
        pursuer_speed=args.pursuer_speed,
        evader_speed=args.evader_speed,
        dt=args.dt,
        max_time=args.max_time,
        capture_radius=args.capture_radius,
        lookahead_steps=args.lookahead,
        n_headings=args.headings,
    )

    print(f"Captured: {result['captured']}")
    print(f"Final time: {result['time']:.3f}")
    print(f"Final separation: {result['distances'][-1]:.3f}")

    plot_result(result, args.capture_radius, save=args.save)

    if args.save is None:
        plot_distance(result)


if __name__ == "__main__":
    main()
