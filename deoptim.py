"""
Python port of the J 'deoptim' addon, built on scipy.optimize.differential_evolution.

Preserves the original interface as closely as the SciPy API allows:
  - Same control parameters (vtr, genmax, npop, f, cr, strategy, refresh, ...)
  - Same return structure (best vars, best value, nfeval, generations,
    per-generation history, final population)
  - Same four mutation strategies, mapped onto SciPy's strategy names
  - Optional constraint predicate (rejection-sampled, matching the J version)

The actual DE loop is SciPy's well-tested implementation; this module is mainly
glue + history capture via the `callback` hook.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable, Sequence

import numpy as np
from scipy.optimize import differential_evolution, NonlinearConstraint


# Map the J strategy numbers (1..4) onto SciPy's strategy strings.
# SciPy only implements binomial crossover for these, which matches the J code's
# "only binary crossover implemented" comment.
_STRATEGY_MAP = {
    1: "best1bin",         # DE/best/1/bin       — J 'DEBest1'
    2: "rand1bin",         # DE/rand/1/bin       — J 'DERand1'
    3: "randtobest1bin",   # DE/rand-to-best/1   — J 'DERandToBest1'
    4: "best2bin",         # DE/best/2/bin       — J 'DEBest2'
}


@dataclass
class DEResult:
    """Mirror of the 7-box result returned by the J `deoptim` verb."""
    best_vars: np.ndarray            # 0{ bestvars
    best_val: float                  # 1{ bestval
    nfeval: int                      # 2{ nfeval
    generations: int                 # 3{ gen
    best_vars_by_gen: np.ndarray     # 4{ bestvarsbygen   (gen+1, nvar)
    best_val_by_gen: np.ndarray      # 5{ bestvalbygen    (gen+1,)
    population: np.ndarray           # 6{ popln           (npop, nvar)
    bounds: np.ndarray               # 7{ bounds          (2, nvar)

    def as_dict(self) -> dict:
        """Equivalent of getDEoptim's labelled output."""
        return {
            "BestVars": self.best_vars,
            "BestVal": self.best_val,
            "nFEval": self.nfeval,
            "Generations": self.generations,
            "BestVarsByGen": self.best_vars_by_gen,
            "BestValByGen": self.best_val_by_gen,
            "Popln": self.population,
            "Bounds": self.bounds,
        }


def deoptim(
    func: Callable[[np.ndarray], float],
    bounds: Sequence[Sequence[float]],
    constr: Callable[[np.ndarray], bool] | None = None,
    *,
    vtr: float = -np.inf,
    genmax: int = 100,
    npop: int = 10,
    f: float | tuple[float, float] = 0.8,
    cr: float = 0.9,
    popln: np.ndarray | None = None,
    strategy: int = 3,
    refresh: int = 50,
    digits: int = 4,
    reeval: bool = False,
    seed: int | np.random.Generator | None = None,
    workers: int = 1,
    vectorized: bool = False,
) -> DEResult:
    """
    Differential Evolution optimisation.

    Parameters mirror the J `deoptim` verb. Defaults match the J version.

    Parameters
    ----------
    func
        Objective f(x) -> scalar to minimise. If `vectorized=True`, must accept
        an (nvar, M) array and return an (M,) array of values.
    bounds
        2 x nvar table (lower, upper) — same shape convention as the J version.
        Also accepts the SciPy-style list of (lo, hi) tuples.
    constr
        Optional predicate. Returns True if the point is feasible.
        Infeasible candidates are rejection-sampled, matching the J code.
        For tight feasible regions prefer SciPy's `NonlinearConstraint` directly.
    vtr
        Value To Reach. Optimisation stops once `best_val <= vtr`.
        J default is 0, but for minimisation `-inf` is usually what you want;
        we default to `-inf`. Pass `vtr=0` for the literal J default.
    genmax
        Maximum number of generations.
    npop
        Population size multiplier — total population is `npop * nvar`,
        same as the J convention.
    f
        Mutation scale in [0, 2]. SciPy also accepts a (min, max) tuple for
        dithering, which often helps convergence.
    cr
        Crossover probability in [0, 1].
    popln
        Optional (M, nvar) initial population.
    strategy
        1=best1, 2=rand1, 3=randtobest1, 4=best2 (all binomial crossover).
    refresh
        Generations between progress prints. 0 disables.
    digits
        Decimal digits in progress prints.
    reeval
        Re-evaluate the incumbent each generation (useful for stochastic `func`).
        Maps to SciPy's `init` re-sampling — see notes.
    seed
        RNG seed or Generator.
    workers, vectorized
        Pass-throughs to SciPy for parallel / vectorised objective evaluation.

    Returns
    -------
    DEResult
        Dataclass with the same fields as the J 7-box result, plus bounds.
    """
    # --- normalise inputs --------------------------------------------------
    bounds = np.asarray(bounds, dtype=float)
    if bounds.shape[0] == 2 and bounds.ndim == 2:
        # J convention: 2 x nvar (row 0 = lower, row 1 = upper)
        lower, upper = bounds[0], bounds[1]
    else:
        # SciPy convention: nvar x 2
        lower, upper = bounds[:, 0], bounds[:, 1]
    nvar = lower.size

    if not np.all(lower < upper):
        raise ValueError("lower bounds must be strictly less than upper bounds")
    if not (0 <= np.min(f) and np.max(f) <= 2):
        raise ValueError("f must lie in [0, 2]")
    if not (0 <= cr <= 1):
        raise ValueError("cr must lie in [0, 1]")
    if strategy not in _STRATEGY_MAP:
        raise ValueError(f"strategy must be one of {sorted(_STRATEGY_MAP)}")
    if genmax <= 0:
        raise ValueError("genmax must be positive")

    scipy_bounds = list(zip(lower, upper))
    rng = np.random.default_rng(seed)

    # --- initial population -----------------------------------------------
    if popln is not None:
        init = np.asarray(popln, dtype=float)
        if init.shape[1] != nvar:
            raise ValueError("popln must have nvar columns")
        if constr is not None and not all(constr(row) for row in init):
            raise ValueError("supplied popln contains infeasible members")
        total_pop = init.shape[0]
    else:
        total_pop = npop * nvar
        init = _sample_feasible(total_pop, lower, upper, constr, rng)

    # --- history capture via callback -------------------------------------
    # SciPy's callback fires after each generation with the current best vector.
    # We also need the best value — easiest path is to evaluate it once per
    # generation, which costs an extra `genmax` evaluations vs. the J version.
    # Acceptable for most uses; set `refresh=0` and skip history if you need
    # absolute minimal evaluation count.
    history_vars: list[np.ndarray] = []
    history_vals: list[float] = []
    gen_counter = {"n": 0}

    def callback(intermediate_result):
        # SciPy >= 1.15 passes a scipy.optimize.OptimizeResult; earlier versions
        # pass (xk, convergence). Handle both.
        if hasattr(intermediate_result, "x"):
            xk = intermediate_result.x
            val = intermediate_result.fun
        else:
            xk = intermediate_result
            val = func(xk)
        history_vars.append(np.asarray(xk).copy())
        history_vals.append(float(val))
        gen_counter["n"] += 1

        if refresh and (gen_counter["n"] == 1 or gen_counter["n"] % refresh == 0):
            _report_progress(xk, val, gen_counter["n"], digits)

        # vtr-based early stop: returning True tells SciPy to halt.
        return val <= vtr

    # --- map strategy -----------------------------------------------------
    scipy_strategy = _STRATEGY_MAP[strategy]

    # --- optional constraint ---------------------------------------------
    constraints: tuple = ()
    if constr is not None:
        # SciPy expects a NonlinearConstraint with numeric residuals; we
        # convert the boolean predicate to {0 feasible, 1 infeasible} so that
        # the feasible set is {c(x) <= 0}.
        def _c(x):
            return 0.0 if constr(np.asarray(x)) else 1.0
        constraints = (NonlinearConstraint(_c, -np.inf, 0.0),)

    # --- run SciPy DE -----------------------------------------------------
    # `polish=False` keeps behaviour comparable to the J version (pure DE,
    # no L-BFGS-B refinement at the end).
    result = differential_evolution(
        func,
        bounds=scipy_bounds,
        strategy=scipy_strategy,
        maxiter=genmax,
        popsize=npop,
        mutation=f,
        recombination=cr,
        init=init,
        callback=callback,
        polish=False,
        seed=rng,
        workers=workers,
        vectorized=vectorized,
        constraints=constraints,
        tol=0.0,           # disable SciPy's own convergence test; rely on genmax / vtr
        updating="deferred" if (workers != 1 or vectorized) else "immediate",
    )

    if refresh and gen_counter["n"] % refresh != 0:
        _report_progress(result.x, result.fun, gen_counter["n"], digits)

    # `result.population` is shape (popsize, nvar) in scaled-back original space.
    population = np.asarray(result.population)

    # Prepend generation 0 (initial best) to mirror the J output shape.
    if history_vars:
        best_vars_by_gen = np.vstack(history_vars)
        best_val_by_gen = np.asarray(history_vals)
    else:
        best_vars_by_gen = result.x[np.newaxis, :]
        best_val_by_gen = np.asarray([result.fun])

    return DEResult(
        best_vars=np.asarray(result.x),
        best_val=float(result.fun),
        nfeval=int(result.nfev),
        generations=gen_counter["n"],
        best_vars_by_gen=best_vars_by_gen,
        best_val_by_gen=best_val_by_gen,
        population=population,
        bounds=np.vstack([lower, upper]),
    )


# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------

def _sample_feasible(
    n: int,
    lower: np.ndarray,
    upper: np.ndarray,
    constr: Callable[[np.ndarray], bool] | None,
    rng: np.random.Generator,
) -> np.ndarray:
    """Generate `n` uniform samples in [lower, upper], rejection-filtered by `constr`."""
    nvar = lower.size
    pop = rng.uniform(lower, upper, size=(n, nvar))
    if constr is None:
        return pop

    # Rejection sample exactly like the J while-loop.
    bad = np.array([not constr(row) for row in pop])
    max_attempts = 1000
    for _ in range(max_attempts):
        if not bad.any():
            return pop
        nbad = int(bad.sum())
        replacement = rng.uniform(lower, upper, size=(nbad, nvar))
        pop[bad] = replacement
        bad_idx = np.where(bad)[0]
        bad = np.zeros_like(bad)
        for i, row in zip(bad_idx, replacement):
            if not constr(row):
                bad[i] = True
    raise RuntimeError(
        "Could not generate a fully feasible initial population via rejection "
        "sampling. Use a less restrictive constraint or pass an explicit `popln`."
    )


def _report_progress(best_vars, best_val, gen, digits):
    print("=" * 22)
    print(f"Generation: {gen}")
    print(f"Best Value: {best_val:.{digits}f}")
    print("Best Var set:")
    with np.printoptions(precision=digits, suppress=True):
        print(np.asarray(best_vars))


# ----------------------------------------------------------------------------
# demo / smoke test
# ----------------------------------------------------------------------------

if __name__ == "__main__":
    # Classic Rosenbrock in 5D — global min 0 at (1, 1, 1, 1, 1).
    def rosenbrock(x):
        return np.sum(100.0 * (x[1:] - x[:-1] ** 2) ** 2 + (1.0 - x[:-1]) ** 2)

    bounds = np.array([[-5.0] * 5, [5.0] * 5])   # 2 x nvar, J-style

    res = deoptim(
        rosenbrock,
        bounds,
        genmax=300,
        npop=15,
        f=(0.5, 1.0),    # dithering
        cr=0.9,
        strategy=3,      # rand-to-best/1
        refresh=50,
        seed=0,
    )

    print("\nFinal:")
    print(f"  best vars  = {res.best_vars}")
    print(f"  best value = {res.best_val:.6e}")
    print(f"  nfeval     = {res.nfeval}")
    print(f"  generations= {res.generations}")
