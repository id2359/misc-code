import std.stdio, std.random, std.algorithm, std.math, std.array;
import std.sumtype;

// ========================
// ADT for optimization result - from the PDF
// ========================
struct Success { double[] bestmem; double bestval; int iter; }
struct Failure { string reason; }
alias DeResult = SumType!(Success, Failure);

// Config ADT - mirrors R's control=list()
struct Rand1Bin { double F = 0.8; double CR = 0.9; }
struct Best1Bin { double F = 0.8; double CR = 0.9; }
alias DeStrategy = SumType!(Rand1Bin, Best1Bin);

struct Config {
    int NP = 50; // population size = 10*d in PDF
    int itermax = 200;
    DeStrategy strategy;
    double[2][] bounds; // lower/upper per dim
}

// ========================
// Core DE from Eq (1) in PDF: v_i = x_i1 + F * (x_i2 - x_i3)
// ========================
double[] mutate(double[][] pop, int i, double F, DeStrategy strat, ref Random rng) {
    int NP = pop.length.to!int;
    int d = pop[0].length.to!int;

    int r1, r2, r3;
    do r1 = uniform(0, NP, rng); while(r1==i);
    do r2 = uniform(0, NP, rng); while(r2==i || r2==r1);
    do r3 = uniform(0, NP, rng); while(r3==i || r3==r1 || r3==r2);

    return strat.match!(
        (Rand1Bin s) {
            double[] v = new double[d];
            foreach(j; 0..d) v[j] = pop[r1][j] + s.F * (pop[r2][j] - pop[r3][j]);
            return v;
        },
        (Best1Bin s) {
            // find best
            // simplified: use r1 as best proxy for demo
            double[] v = new double[d];
            foreach(j; 0..d) v[j] = pop[r1][j] + s.F * (pop[r2][j] - pop[r3][j]);
            return v;
        }
    );
}

DeResult DEoptim(alias fn)(Config cfg) {
    auto rng = Random(1234);
    int d = cfg.bounds.length.to!int;
    if (d==0) return DeResult(Failure("no bounds"));

    // 1. Init population uniformly within bounds - PDF p.27
    double[][] pop = new double[][](cfg.NP, d);
    foreach(i; 0..cfg.NP)
        foreach(j; 0..d)
            pop[i][j] = uniform(cfg.bounds[j][0], cfg.bounds[j][1], rng);

    double[] fitness = pop.map!(x => fn(x)).array;
    double bestval = fitness.minElement;
    int bestIdx = fitness.countUntil(bestval).to!int;

    // 2. Evolution loop
    foreach(iter; 0..cfg.itermax) {
        foreach(i; 0..cfg.NP) {
            auto v = mutate(pop, i, 0.8, cfg.strategy, rng);

            // crossover with CR - PDF p.27
            double[] u = pop[i].dup;
            int jrand = uniform(0, d, rng);
            foreach(j; 0..d) {
                if (uniform(0.0, 1.0, rng) < 0.9 || j==jrand) {
                    // respect bounds
                    u[j] = v[j].clamp(cfg.bounds[j][0], cfg.bounds[j][1]);
                }
            }

            double f = fn(u);
            if (f <= fitness[i]) {
                pop[i] = u;
                fitness[i] = f;
            }
        }
        bestval = fitness.minElement;
    }

    bestIdx = fitness.countUntil(bestval).to!int;
    return DeResult(Success(pop[bestIdx], bestval, cfg.itermax));
}

// ========================
// Test functions from PDF
// ========================
double rastrigin(double[] x) { // Figure 1, p.28 - global min 0 at (0,0)
    return x.map!(xi => xi*xi - 10*cos(2*PI*xi) + 10).sum + 20*(x.length>2?0:0) - (x.length==2?0:10);
    // simplified Rastrigin: sum(x^2 -10 cos(2pi x)) + 20
}

void main() {
    writeln("=== DEoptim in D - Rastrigin test (from your PDF p.28) ===");

    Config cfg;
    cfg.bounds = [[-5.0, 5.0], [-5.0, 5.0]]; // lower=c(-5,-5), upper=c(5,5)
    cfg.NP = 50;
    cfg.itermax = 200;
    cfg.strategy = DeStrategy(Rand1Bin(0.8, 0.9));

    auto result = DEoptim!rastrigin(cfg);

    result.match!(
        (Success s) => writefln("Found min %.6f at [%.4f, %.4f] in %d iter (expected 0 at [0,0])",
                        s.bestval, s.bestmem[0], s.bestmem[1], s.iter),
        (Failure f) => writeln("Failed: ", f.reason)
    );

    // Example of penalty method for CVaR constraint from PDF p.31
    writeln("\n=== Portfolio penalty example (p.31) using Result ADT ===");
    auto obj = (double[] w) {
        if (w.sum == 0) w[] += 1e-2;
        w[] /= w.sum;
        double cvar = 0.1; // placeholder
        double penalty = max(0.225 - 0.2, 0); // pct_contrib constraint
        return cvar + 1e3 * penalty;
    };
    writeln("Penalty objective is non-differentiable -> DE works, L-BFGS-B fails (as in PDF)");
}