# Figaro Probabilistic Programming Cheatsheet

Probabilistic Programming (PPL) allows you to write code that represents a **Generative Model** of the world. You define how variables interact, provide observations (evidence), and the computer "runs the code in reverse" to find the most likely causes.

---

## 1. Core Building Blocks: `Element[T]`
Every variable in Figaro is an `Element`.

### Atomic Elements (Basic Distributions)
```scala
val flip = Flip(0.5)               // Boolean: true with prob 0.5
val roll = Select(0.1 -> 1, 0.9 -> 2) // Discrete: 1 (10%) or 2 (90%)
val score = Normal(70, 10)         // Continuous: Mean 70, StdDev 10
val rate = Exponential(0.5)        // Continuous: Exponential distribution
val fix = Constant(5.0)            // Always returns 5.0
```

### Compound Elements (Logic & Math)
Use these to link variables together.
```scala
// Apply: Simple transformation (A -> B)
val doubleScore = Apply(score, (s: Double) => s * 2)

// Chain: Dependency where the choice of the second element depends on the first
val result = Chain(flip, (f: Boolean) => if (f) Normal(10, 1) else Normal(0, 1))

// Logic Operators
val both = flip1 && flip2
val either = flip1 || flip2
val choice = If(flip, score1, score2)
```

---

## 2. The "Proper" PPL Workflow

### Step A: Define the Generative Model
Write code that describes how the data is produced.
```scala
val quality = Uniform(0, 1)
val success = Flip(quality) // Success depends on quality
```

### Step B: Attach Evidence (The "Reverse" bit)
Tell the model what you actually observed in the real world.
```scala
// Condition: Hard Boolean requirement
success.observe(true) 

// Constraint: Soft "Likelihood" (how well data fits)
// Use log-density for numerical stability in complex models
score.setLogConstraint(x => -math.pow(x - 75.0, 2) / 2.0)
```

### Step C: Run Inference
Choose an algorithm to solve for the unknown variables.
```scala
val alg = Importance(10000, quality)
alg.run()
```

### Step D: Query the Posterior
Ask for the result.
```scala
val meanQuality = alg.expectation(quality, (q: Double) => q)
val probHighQuality = alg.probability(quality, (q: Double) => q > 0.8)
alg.kill()
```

---

## 3. Choosing the Right Algorithm

| Algorithm | Type | Best For... | Cons |
| :--- | :--- | :--- | :--- |
| **VariableElimination** | Factored | Small models, discrete variables. **Exact** results. | Explodes in complexity; hates continuous vars. |
| **Importance** | Sampling | Forward-flowing models (Predictions). Fast. | Struggles if evidence is extremely "unlikely." |
| **MetropolisHastings** | MCMC | Complex models with many constraints (Training). | Can get "stuck" in local areas; needs many samples. |
| **ParticleFilter** | Sampling | Time-series data where you update state week-by-week. | Harder to implement for beginners. |

---

## 4. Pro-Tips for Success

1.  **Numerical Dissipation:** In recursive models (like the Protest app), values tend to decay to 0 over time. Always use **Bias/Intercept** terms to maintain a baseline.
2.  **Regularization:** If your training results are "wild" (huge numbers), your **Priors** are too loose. Switch from Cauchy to Normal distributions with smaller standard deviations.
3.  **Naming:** Use `NamedElement` or provide names in constructors (`Normal(0, 1, "myVar")`) to make debugging and error messages much more readable.
4.  **Resource Cleanup:** Always call `alg.kill()` when finished. Figaro uses Akka actors under the hood; failing to kill them will leak memory and threads.
5.  **Discretization:** If you must use `VariableElimination` with continuous variables, Figaro will "discretize" them (pick 15-20 points). This is often very inaccurate for narrow distributions.
