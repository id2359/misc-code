#!/usr/bin/env python3

import cmath
import math
from dataclasses import dataclass


@dataclass
class PeriodicGrid:
    n: int
    length: float = 2.0 * math.pi

    def points(self):
        step = self.length / self.n
        return [j * step for j in range(self.n)]

    def frequencies(self):
        half = self.n // 2
        return [k if k < half else k - self.n for k in range(self.n)]


class PseudoDifferentialOperator:
    def __init__(self, grid: PeriodicGrid, symbol):
        self.grid = grid
        self.symbol = symbol

    def apply(self, u):
        x = self.grid.points()
        xi = self.grid.frequencies()
        u_hat = dft(u, x, xi)
        out = []
        for xj in x:
            total = 0j
            for k, xik in enumerate(xi):
                total += self.symbol(xj, xik) * u_hat[k] * cmath.exp(1j * xik * xj)
            out.append(total)
        return out


def dft(u, x, xi):
    n = len(u)
    coeffs = []
    for xik in xi:
        total = 0j
        for j, xj in enumerate(x):
            total += u[j] * cmath.exp(-1j * xik * xj)
        coeffs.append(total / n)
    return coeffs


def demo_symbol(x, xi):
    return math.sqrt(1.0 + xi**2) + 0.35 * math.cos(2.0 * x)


def test_function(x):
    return math.sin(3.0 * x) + 0.5 * math.cos(5.0 * x) + 0.2 * math.sin(7.0 * x)


def split_form_reference(grid: PeriodicGrid, u):
    x = grid.points()
    xi = grid.frequencies()
    u_hat = dft(u, x, xi)
    multiplier_part = []
    for xj in x:
        total = 0j
        for k, xik in enumerate(xi):
            total += math.sqrt(1.0 + xik**2) * u_hat[k] * cmath.exp(1j * xik * xj)
        multiplier_part.append(total.real)
    return [multiplier_part[j] + 0.35 * math.cos(2.0 * x[j]) * u[j] for j in range(grid.n)]


def l2_norm(values):
    return math.sqrt(sum((abs(v) ** 2 for v in values)))


def main() -> None:
    grid = PeriodicGrid(n=48)
    x = grid.points()
    u = [test_function(xj) for xj in x]
    op = PseudoDifferentialOperator(grid, demo_symbol)
    result = [z.real for z in op.apply(u)]
    reference = split_form_reference(grid, u)
    rel_err = l2_norm([a - b for a, b in zip(result, reference)]) / l2_norm(reference)

    print("Pseudo-differential operator demo (Python)")
    print(f"grid points: {grid.n}")
    print(f"relative consistency error: {rel_err:.3e}")
    print("")
    print("sample values:")
    for j in range(5):
        print(f"x={x[j]:7.4f}  u={u[j]: .6f}  Op(a)u={result[j]: .6f}")


if __name__ == "__main__":
    main()
