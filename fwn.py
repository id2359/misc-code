#!/usr/bin/env python3
"""
fwn.py -- minimal Fuzzy Wavelet Network demo.

Educational, small version of a FWN:
  * 1-D input, 1-D output
  * Gaussian fuzzy memberships
  * each fuzzy rule owns a small bank of Mexican-hat wavelets
  * output weights are fitted by least squares

Run:
    python3 fwn.py
"""

import numpy as np


def mexican_hat(z):
    """Mexican-hat / Ricker-style wavelet."""
    return (1.0 - z * z) * np.exp(-0.5 * z * z)


def target_function(x):
    """A small nonlinear test function."""
    return np.sin(2.0 * x) + 0.3 * np.cos(7.0 * x)


class FWN:
    def __init__(self, rule_centres, rule_width, wavelet_centres, scales):
        self.rule_centres = np.asarray(rule_centres, dtype=float)
        self.rule_width = float(rule_width)
        self.wavelet_centres = np.asarray(wavelet_centres, dtype=float)
        self.scales = np.asarray(scales, dtype=float)

        self.n_rules = len(self.rule_centres)
        self.n_wavelets = len(self.wavelet_centres)

        # One linear coefficient per (rule, wavelet), plus one bias.
        self.weights = np.zeros(self.n_rules * self.n_wavelets + 1)

    def memberships(self, x):
        """
        Normalized fuzzy firing strengths.

        Returns an array of shape:
            len(x) by n_rules
        """
        x = np.asarray(x, dtype=float)
        raw = np.exp(-0.5 * ((x[:, None] - self.rule_centres[None, :]) / self.rule_width) ** 2)
        return raw / raw.sum(axis=1, keepdims=True)

    def design_matrix(self, x):
        """
        Build regression matrix.

        For each input x:
          feature(i,k) = normalized_membership_i(x) * wavelet_k_at_rule_i(x)
        """
        x = np.asarray(x, dtype=float)
        mu = self.memberships(x)

        cols = []
        for i in range(self.n_rules):
            scale = self.scales[i]
            z = (x[:, None] - self.wavelet_centres[None, :]) / scale
            psi = mexican_hat(z)
            cols.append(mu[:, [i]] * psi)

        phi = np.hstack(cols)
        bias = np.ones((len(x), 1))
        return np.hstack([phi, bias])

    def fit(self, x, y):
        phi = self.design_matrix(x)
        self.weights, *_ = np.linalg.lstsq(phi, y, rcond=None)
        return self

    def predict(self, x):
        return self.design_matrix(x) @ self.weights


def main():
    rng = np.random.default_rng(1)

    x_train = np.linspace(-3.0, 3.0, 80)
    y_train = target_function(x_train)

    # Fuzzy rules: coarse partition of input space.
    rule_centres = [-2.0, 0.0, 2.0]
    rule_width = 1.4

    # Wavelet centres: same small wavelet bank used inside each rule.
    wavelet_centres = np.linspace(-3.0, 3.0, 13)

    # One scale per rule. Smaller scale = more local/detail.
    scales = [1.2, 0.8, 1.2]

    model = FWN(rule_centres, rule_width, wavelet_centres, scales).fit(x_train, y_train)

    x_test = np.linspace(-3.0, 3.0, 200)
    y_test = target_function(x_test)
    y_hat = model.predict(x_test)

    rmse = np.sqrt(np.mean((y_hat - y_test) ** 2))

    print("Minimal FWN demo")
    print("----------------")
    print("rules:", model.n_rules)
    print("wavelets per rule:", model.n_wavelets)
    print("parameters:", len(model.weights))
    print("test RMSE:", rmse)
    print()
    print("first 10 predictions:")
    for x, y, yh in zip(x_test[:10], y_test[:10], y_hat[:10]):
        print(f"x={x: .3f}  target={y: .6f}  fwn={yh: .6f}")


if __name__ == "__main__":
    main()
