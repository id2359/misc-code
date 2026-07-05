"""
psido.py — a small symbol-based framework for pseudodifferential operators
on a 1D periodic domain, built on FFT.

Two operator classes, mirroring the two regimes you actually meet in practice:

  FourierMultiplier
      Symbol depends only on xi (constant-coefficient / translation-invariant
      operator). Application is O(N log N) via FFT. Composition, adjoints,
      and (regularized) inverses are all pointwise operations on the symbol —
      this is the easy, exact case, and it's what most "PsiDO-flavoured"
      signal processing (fractional derivatives, elliptic smoothers, apodizing
      filters) actually reduces to.

  KohnNirenberg
      Symbol depends on (x, xi): a genuine variable-coefficient PsiDO.
      Quantized directly via
          (Op(a) u)(x) = (1/N) * sum_k a(x, xi_k) * u_hat(xi_k) * e^{i xi_k x}
      which is O(N^2) — fine as a reference/validation implementation or for
      moderate grid sizes, not for production-scale transforms. Includes the
      standard first-order symbol calculus for composition:
          sigma(A B)(x, xi) ~ a(x,xi) b(x,xi) + (1/i) d_xi a * d_x b + O(order -2)

Convention: periodic grid of length L, N points, angular frequencies via
np.fft.fftfreq (so this matches numpy's FFT ordering directly — no fftshift
bookkeeping needed unless you're plotting the symbol).
"""

from __future__ import annotations
import numpy as np


class Grid:
    def __init__(self, N: int, L: float = 2 * np.pi):
        self.N, self.L = N, L
        self.x = np.linspace(0, L, N, endpoint=False)
        self.xi = 2 * np.pi * np.fft.fftfreq(N, d=L / N)  # angular frequency, fft order


class FourierMultiplier:
    """Constant-coefficient PsiDO: symbol a(xi) only."""

    def __init__(self, grid: Grid, symbol_fn):
        self.grid = grid
        self.symbol_fn = symbol_fn
        self.symbol = symbol_fn(grid.xi)

    def __call__(self, u: np.ndarray) -> np.ndarray:
        return np.fft.ifft(self.symbol * np.fft.fft(u))

    def adjoint(self) -> "FourierMultiplier":
        return FourierMultiplier(self.grid, lambda xi: np.conj(self.symbol_fn(xi)))

    def compose(self, other: "FourierMultiplier") -> "FourierMultiplier":
        # Exact for Fourier multipliers: symbols just multiply.
        return FourierMultiplier(self.grid, lambda xi: self.symbol_fn(xi) * other.symbol_fn(xi))

    def parametrix(self, eps: float = 1e-10) -> "FourierMultiplier":
        """Approximate inverse (1/symbol, zeroed near the symbol's zero set)."""
        def inv(xi):
            s = self.symbol_fn(xi)
            safe = np.where(s == 0, 1, s)
            return np.where(np.abs(s) > eps, 1.0 / safe, 0.0)
        return FourierMultiplier(self.grid, inv)


class KohnNirenberg:
    """General PsiDO with symbol a(x, xi), Kohn-Nirenberg quantized. O(N^2)."""

    def __init__(self, grid: Grid, symbol_fn):
        self.grid = grid
        self.symbol_fn = symbol_fn
        X, XI = np.meshgrid(grid.x, grid.xi, indexing="ij")  # both (N, N)
        self.A = symbol_fn(X, XI)
        self.phase = np.exp(1j * XI * X)

    def __call__(self, u: np.ndarray) -> np.ndarray:
        u_hat = np.fft.fft(u)
        return (self.A * self.phase * u_hat[np.newaxis, :]).sum(axis=1) / self.grid.N

    def freeze_at(self, x0: float) -> FourierMultiplier:
        """Frozen-coefficient Fourier multiplier at x = x0 (local/principal symbol)."""
        return FourierMultiplier(self.grid, lambda xi: self.symbol_fn(x0, xi))

    def leading_symbol_composition(self, other: "KohnNirenberg", dx: float = 1e-6):
        """
        First-order asymptotic symbol of self ∘ other. Returns a callable
        symbol(x, xi), not an operator, since the exact composition of two
        full PsiDOs isn't itself closed-form Kohn-Nirenberg quantizable.
        """
        a, b = self.symbol_fn, other.symbol_fn

        def sigma(x, xi):
            da_dxi = (a(x, xi + dx) - a(x, xi - dx)) / (2 * dx)
            db_dx = (b(x + dx, xi) - b(x - dx, xi)) / (2 * dx)
            return a(x, xi) * b(x, xi) + da_dxi * db_dx / 1j

        return sigma


# --------------------------------------------------------------------------
# Demonstration / sanity checks
# --------------------------------------------------------------------------
if __name__ == "__main__":
    g = Grid(N=256, L=2 * np.pi)

    # 1. Fractional Laplacian (-d^2/dx^2)^{s/2}, symbol |xi|^s.
    #    Check against the exact result on a single Fourier mode.
    s = 1.5
    frac_lap = FourierMultiplier(g, lambda xi: np.abs(xi) ** s)
    k = 3
    u = np.exp(1j * k * g.x)
    out = frac_lap(u)
    expected = (abs(k) ** s) * u
    print("fractional Laplacian max error:", np.max(np.abs(out - expected)))

    # 2. Bessel-potential smoother (1+xi^2)^{-s/2} — a genuinely elliptic,
    #    everywhere-nonvanishing symbol; useful as a regularizer (e.g. in a
    #    calibration/deconvolution context where you want a smooth,
    #    invertible pseudodifferential preconditioner rather than a hard
    #    frequency cutoff).
    smoother = FourierMultiplier(g, lambda xi: (1 + xi ** 2) ** (-1.0))
    inv_smoother = smoother.parametrix()
    roundtrip = inv_smoother(smoother(u))
    print("smoother parametrix roundtrip error:", np.max(np.abs(roundtrip - u)))

    # 3. Variable-coefficient example: a spatially-varying low-pass filter,
    #    i.e. an apodization/taper whose cutoff width depends on position
    #    (the PsiDO analogue of a beam- or baseline-dependent taper). This
    #    is a genuine KohnNirenberg operator — its symbol is not separable.
    def taper_symbol(x, xi):
        width = 5 + 20 * np.sin(x / 2) ** 2  # cutoff varies with x
        return np.exp(-(xi ** 2) / (2 * width ** 2))

    variable_filter = KohnNirenberg(g, taper_symbol)
    noisy = np.sin(3 * g.x) + 0.3 * np.random.default_rng(0).standard_normal(g.N)
    filtered = variable_filter(noisy)
    print("variable-taper output sample:", filtered[:5].real)

    # Local/principal symbol at a point, as a cheap FourierMultiplier:
    local_op = variable_filter.freeze_at(x0=np.pi)
    print("frozen-coefficient symbol at x=pi, xi=1:", local_op.symbol_fn(1.0))
