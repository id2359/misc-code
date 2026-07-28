#!/usr/bin/env python3
"""Least-squares parameter estimation example using NumPy and SciPy.

This script fits an exponential-decay model to noisy synthetic data:

    y = a * exp(-b * x) + c

It shows:
1. How to define a parameterized model with NumPy.
2. How to define residuals for least-squares estimation.
3. How to solve for the parameters with scipy.optimize.least_squares.
4. How to inspect fit quality with the residual norm and RMSE.
"""

from __future__ import annotations

import numpy as np
from scipy.optimize import least_squares


def model(x: np.ndarray, params: np.ndarray) -> np.ndarray:
    """Exponential-decay model with parameters [a, b, c]."""
    a, b, c = params
    return a * np.exp(-b * x) + c


def residuals(params: np.ndarray, x: np.ndarray, y_obs: np.ndarray) -> np.ndarray:
    """Residual vector: model prediction minus observed data."""
    return model(x, params) - y_obs


def main() -> None:
    rng = np.random.default_rng(7)

    # Synthetic data generated from known parameters plus noise.
    true_params = np.array([2.5, 1.3, 0.5])
    x = np.linspace(0.0, 4.0, 40)
    y_clean = model(x, true_params)
    y_obs = y_clean + rng.normal(loc=0.0, scale=0.08, size=x.shape)

    initial_guess = np.array([1.0, 0.2, 0.0])

    result = least_squares(
        residuals,
        x0=initial_guess,
        args=(x, y_obs),
    )

    fitted_params = result.x
    fit_residuals = residuals(fitted_params, x, y_obs)
    rmse = np.sqrt(np.mean(fit_residuals**2))

    print("Least-squares estimation with SciPy")
    print("----------------------------------")
    print(f"True parameters     : {true_params}")
    print(f"Initial guess       : {initial_guess}")
    print(f"Estimated parameters: {fitted_params}")
    print(f"Cost (1/2 ||r||^2)  : {result.cost:.6f}")
    print(f"Residual RMSE       : {rmse:.6f}")
    print(f"Converged           : {result.success}")
    print(f"Solver message      : {result.message}")

    # Optional NumPy-only comparison for a linear least-squares problem:
    # fit y ≈ m*x + d to the same observations using np.linalg.lstsq.
    design = np.column_stack([x, np.ones_like(x)])
    linear_params, *_ = np.linalg.lstsq(design, y_obs, rcond=None)
    m, d = linear_params
    print()
    print("NumPy linear least-squares comparison")
    print("-------------------------------------")
    print(f"Best-fit line: y ≈ {m:.6f} * x + {d:.6f}")


if __name__ == "__main__":
    main()
