#!/usr/bin/env python3
"""
full_fwn.py -- fuller educational Fuzzy Wavelet Network with EKF.

This is a practical, readable implementation of the paper's training pattern:

    1. Fuzzy rules give normalized firing strengths.
    2. Each rule owns a sub-wavelet network.
    3. Nonlinear parameters are learned by an Extended Kalman Filter:
          - fuzzy rule centres
          - fuzzy rule log-widths
          - wavelet centres / translations
          - wavelet log-scales / dilations
    4. Linear output weights are refreshed by least squares.

Still simplified versus the IEEE paper:
    - 1-D input, 1-D output
    - fixed number of fuzzy rules
    - fixed number of wavelets per rule
    - no OLS wavelet pruning
    - numerical Jacobian for clarity instead of hand-derived derivatives

Run:
    python3 full_fwn.py

Optional plot:
    python3 full_fwn.py --plot
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import numpy as np


def mexican_hat(z: np.ndarray) -> np.ndarray:
    """Mexican-hat / Ricker-style wavelet."""
    return (1.0 - z * z) * np.exp(-0.5 * z * z)


def target_function(x: np.ndarray) -> np.ndarray:
    """Nonlinear test function with coarse and fine structure."""
    return np.sin(2.0 * x) + 0.3 * np.cos(7.0 * x)


@dataclass
class FullFWNConfig:
    n_rules: int = 3
    n_wavelets: int = 9
    x_min: float = -3.0
    x_max: float = 3.0
    initial_rule_width: float = 1.5
    initial_wavelet_scale: float = 0.9
    ekf_epochs: int = 8
    ls_refresh_every: int = 1
    finite_difference_eps: float = 1e-4
    process_noise: float = 1e-5
    measurement_noise: float = 2e-3
    initial_covariance: float = 0.05


class FullFWN:
    """
    1-D Fuzzy Wavelet Network.

    Parameter vector theta contains nonlinear parameters:

        [rule_centres,
         log_rule_widths,
         wavelet_centres flattened rule-major,
         log_wavelet_scales flattened rule-major]

    Linear weights are stored separately and are estimated by least squares.
    """

    def __init__(self, cfg: FullFWNConfig):
        self.cfg = cfg
        self.n_rules = cfg.n_rules
        self.n_wavelets = cfg.n_wavelets

        rule_centres = np.linspace(cfg.x_min, cfg.x_max, cfg.n_rules)
        log_rule_widths = np.full(cfg.n_rules, np.log(cfg.initial_rule_width))

        base_wavelet_centres = np.linspace(cfg.x_min, cfg.x_max, cfg.n_wavelets)
        wavelet_centres = np.tile(base_wavelet_centres, cfg.n_rules)

        log_wavelet_scales = np.full(
            cfg.n_rules * cfg.n_wavelets,
            np.log(cfg.initial_wavelet_scale),
        )

        self.theta = np.concatenate(
            [
                rule_centres,
                log_rule_widths,
                wavelet_centres,
                log_wavelet_scales,
            ]
        )

        # One coefficient per rule-wavelet feature, plus one bias.
        self.weights = np.zeros(cfg.n_rules * cfg.n_wavelets + 1)

        # EKF covariance over nonlinear parameters.
        n_theta = len(self.theta)
        self.P = np.eye(n_theta) * cfg.initial_covariance

    # ------------------------------------------------------------------
    # Parameter unpacking
    # ------------------------------------------------------------------

    def unpack_theta(self, theta: np.ndarray | None = None):
        if theta is None:
            theta = self.theta

        r = self.n_rules
        m = self.n_wavelets
        rm = r * m

        p0 = 0
        rule_centres = theta[p0 : p0 + r]
        p0 += r

        rule_widths = np.exp(theta[p0 : p0 + r])
        p0 += r

        wavelet_centres = theta[p0 : p0 + rm].reshape(r, m)
        p0 += rm

        wavelet_scales = np.exp(theta[p0 : p0 + rm]).reshape(r, m)

        return rule_centres, rule_widths, wavelet_centres, wavelet_scales

    # ------------------------------------------------------------------
    # Forward model
    # ------------------------------------------------------------------

    def memberships(self, x: np.ndarray, theta: np.ndarray | None = None) -> np.ndarray:
        x = np.asarray(x, dtype=float)
        rule_centres, rule_widths, _, _ = self.unpack_theta(theta)

        raw = np.exp(
            -0.5 * ((x[:, None] - rule_centres[None, :]) / rule_widths[None, :]) ** 2
        )

        denom = raw.sum(axis=1, keepdims=True)
        denom = np.maximum(denom, 1e-12)
        return raw / denom

    def design_matrix(self, x: np.ndarray, theta: np.ndarray | None = None) -> np.ndarray:
        x = np.asarray(x, dtype=float)
        _, _, wavelet_centres, wavelet_scales = self.unpack_theta(theta)
        mu = self.memberships(x, theta)

        cols = []
        for i in range(self.n_rules):
            z = (x[:, None] - wavelet_centres[i][None, :]) / wavelet_scales[i][None, :]
            psi = mexican_hat(z)
            cols.append(mu[:, [i]] * psi)

        phi = np.hstack(cols)
        bias = np.ones((len(x), 1))
        return np.hstack([phi, bias])

    def predict_with(self, x: np.ndarray, theta: np.ndarray, weights: np.ndarray) -> np.ndarray:
        return self.design_matrix(x, theta) @ weights

    def predict(self, x: np.ndarray) -> np.ndarray:
        return self.predict_with(x, self.theta, self.weights)

    # ------------------------------------------------------------------
    # Linear least-squares output layer
    # ------------------------------------------------------------------

    def refresh_linear_weights(self, x: np.ndarray, y: np.ndarray) -> None:
        phi = self.design_matrix(x, self.theta)
        self.weights, *_ = np.linalg.lstsq(phi, y, rcond=1e-8)

    # ------------------------------------------------------------------
    # EKF nonlinear update
    # ------------------------------------------------------------------

    def numerical_jacobian_single(self, x_scalar: float) -> np.ndarray:
        """
        Jacobian dy_hat/dtheta for one sample.

        Uses central finite differences. This is slower than analytic derivatives,
        but much easier to check and modify.
        """
        eps = self.cfg.finite_difference_eps
        h = np.zeros_like(self.theta)

        for j in range(len(self.theta)):
            step = eps * (1.0 + abs(self.theta[j]))

            theta_plus = self.theta.copy()
            theta_minus = self.theta.copy()
            theta_plus[j] += step
            theta_minus[j] -= step

            y_plus = self.predict_with(np.array([x_scalar]), theta_plus, self.weights)[0]
            y_minus = self.predict_with(np.array([x_scalar]), theta_minus, self.weights)[0]

            h[j] = (y_plus - y_minus) / (2.0 * step)

        return h

    def ekf_update_single(self, x_scalar: float, y_scalar: float) -> float:
        """
        One scalar-measurement EKF update.

        Returns prediction error before the update.
        """
        q = self.cfg.process_noise
        r_noise = self.cfg.measurement_noise

        # Prediction step: random-walk nonlinear parameters.
        self.P = self.P + q * np.eye(len(self.theta))

        y_hat = self.predict(np.array([x_scalar]))[0]
        err = y_scalar - y_hat

        H = self.numerical_jacobian_single(x_scalar)  # shape: n_theta

        PH = self.P @ H
        S = float(H @ PH + r_noise)
        if S <= 1e-12:
            return err

        K = PH / S

        self.theta = self.theta + K * err

        # Joseph-stable-ish scalar update.
        I = np.eye(len(self.theta))
        KH = np.outer(K, H)
        self.P = (I - KH) @ self.P @ (I - KH).T + r_noise * np.outer(K, K)

        # Keep covariance symmetric.
        self.P = 0.5 * (self.P + self.P.T)

        return err

    # ------------------------------------------------------------------
    # Training
    # ------------------------------------------------------------------

    def fit(self, x: np.ndarray, y: np.ndarray, verbose: bool = True) -> "FullFWN":
        x = np.asarray(x, dtype=float)
        y = np.asarray(y, dtype=float)

        self.refresh_linear_weights(x, y)

        rng = np.random.default_rng(123)

        for epoch in range(1, self.cfg.ekf_epochs + 1):
            order = rng.permutation(len(x))
            sqerr = []

            for idx in order:
                err = self.ekf_update_single(float(x[idx]), float(y[idx]))
                sqerr.append(err * err)

            if epoch % self.cfg.ls_refresh_every == 0:
                self.refresh_linear_weights(x, y)

            train_rmse = float(np.sqrt(np.mean((self.predict(x) - y) ** 2)))

            if verbose:
                print(
                    f"epoch {epoch:02d} | "
                    f"EKF pre-update RMSE {np.sqrt(np.mean(sqerr)):.6f} | "
                    f"post-LS train RMSE {train_rmse:.6f}"
                )

        return self

    # ------------------------------------------------------------------
    # Inspection helpers
    # ------------------------------------------------------------------

    def summary(self) -> str:
        rc, rw, wc, ws = self.unpack_theta()
        lines = []
        lines.append("Full FWN")
        lines.append("--------")
        lines.append(f"rules: {self.n_rules}")
        lines.append(f"wavelets per rule: {self.n_wavelets}")
        lines.append(f"nonlinear parameters: {len(self.theta)}")
        lines.append(f"linear weights: {len(self.weights)}")
        lines.append("")
        lines.append("learned fuzzy rule centres:")
        lines.append(np.array2string(rc, precision=4))
        lines.append("learned fuzzy rule widths:")
        lines.append(np.array2string(rw, precision=4))
        lines.append("")
        lines.append("learned wavelet centre ranges by rule:")
        for i in range(self.n_rules):
            lines.append(
                f"  rule {i}: centres [{wc[i].min():.4f}, {wc[i].max():.4f}], "
                f"scales [{ws[i].min():.4f}, {ws[i].max():.4f}]"
            )
        return "\n".join(lines)


def maybe_plot(model: FullFWN, x_train: np.ndarray, y_train: np.ndarray) -> None:
    import matplotlib.pyplot as plt

    x_test = np.linspace(model.cfg.x_min, model.cfg.x_max, 400)
    y_test = target_function(x_test)
    y_hat = model.predict(x_test)

    plt.figure()
    plt.plot(x_test, y_test, label="target")
    plt.plot(x_test, y_hat, label="FWN")
    plt.scatter(x_train, y_train, s=12, label="training data")
    plt.title("Full FWN approximation")
    plt.xlabel("x")
    plt.ylabel("y")
    plt.legend()
    plt.show()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plot", action="store_true", help="show matplotlib plot")
    parser.add_argument("--epochs", type=int, default=8, help="EKF epochs")
    args = parser.parse_args()

    cfg = FullFWNConfig(ekf_epochs=args.epochs)

    x_train = np.linspace(cfg.x_min, cfg.x_max, 90)
    y_train = target_function(x_train)

    model = FullFWN(cfg)
    print(model.summary())
    print()
    model.fit(x_train, y_train, verbose=True)
    print()
    print(model.summary())

    x_test = np.linspace(cfg.x_min, cfg.x_max, 250)
    y_test = target_function(x_test)
    y_hat = model.predict(x_test)

    rmse = np.sqrt(np.mean((y_hat - y_test) ** 2))
    print()
    print("test RMSE:", rmse)
    print()
    print("first 10 predictions:")
    for x, y, yh in zip(x_test[:10], y_test[:10], y_hat[:10]):
        print(f"x={x: .3f}  target={y: .6f}  fwn={yh: .6f}")

    if args.plot:
        maybe_plot(model, x_train, y_train)


if __name__ == "__main__":
    main()
