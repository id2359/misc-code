/ fuzzy.k - fuzzy on/off controller from Skomorokhov et al.,
/ "Fuzzy Control of Technological Processes in APL2" (APL95), in Kona (K3).
/ Run:  k fuzzy.k
/ Lines starting with "/ " are comments. Careful: " /" mid-line also starts one.

/ ---------- 1. membership functions ----------
/ Five triangular sets: big neg, neg, zero, pos, big pos (peaks equally spaced).
/ Weight of set i = 0 | 1 - |x-peak_i| % spacing ; x is first clamped to the
/ outer peaks so anything past +-200 is "big" with weight 1 (as in the paper).
MuN:-200 -100 0 100 200          / N = Nc-Nd   (deviation from target)
MuD:-100 -50 0 50 100            / D = N[t]-N[t-1]   (rate of change)
abs:{x|-x}                       / | is max, so x|-x is absolute value
/ NB Kona: int%int is INTEGER division (25%100 is 0), so force a float with 1.0*
member:{[x;p] x:(*p)|(*|p)&x; 0|1-abs[x-p]%1.0*p[1]-p 0}
/  (*p) first, (*|p) last, & min, | max

/ ---------- 2. fuzzy AND of every (D-set, N-set) pair ----------
/ o\: is "each-left": row i = d[i] o n.  Pass * (product) or & (min).
fuzzy:{[o;d;n] o\:[d;n]}

/ ---------- 3. rule bases (rows = D set, cols = N set) ----------
RB0:(1 1 1 1 0;1 1 0 0 0;1 1 0 0 0;1 0 0 0 0;0 0 0 0 0)  / machine OFF: 1 = switch on
RB1:(0 0 0 0 1;0 0 0 0 1;0 0 1 1 1;0 0 1 1 1;0 1 1 1 1)  / machine ON : 1 = switch off

/ ---------- 4. decision: rule at the FIRST cell holding the max ----------
/ APL2: ACTION<-(,M=max/,M)/,RB   K: flatten (,/), find first max (?), index
control:{[rb;m] m:,/m; (,/rb)@m?|/m}

/ fuzzy controller: (N;D;state) -> new state.  Action 1 flips the state.
fz:{[n;d;s] a:control[(RB0;RB1)s; fuzzy[*;member[d;MuD];member[n;MuN]]]; ~s=a}
/ naive comparison: on whenever below target, off otherwise
th:{[n;d;s] n<0}
/ RB0 only switches on once N is "negative" (about -50), so the fuzzy loop
/ settles ~50 boxes below target.  Same rules, aimed 50 boxes higher:
fz50:{[n;d;s] fz[n-50;d;s]}
/ (on this plant, with P=60 boxes/step, that ends up making exactly the same
/  decisions as the naive threshold -- try other P / demand to see them differ)

/ ---------- 5. checks against the paper's worked examples ----------
fmt:{$0.01*_ 0.5+100*x}           / round to 2 dp, then format
show:{[t;ok] `0: (-34$t),(("FAIL";"ok")ok),"\n"}
`0: "== checks from the paper ==\n"
show["MEMBER(-25,MuN) = 0 .25 .75 0 0";1e-9>|/abs member[-25;MuN]-0 0.25 0.75 0 0]
M:fuzzy[*;member[5;MuD];member[-50;MuN]]
show["x FUZZY row3 = 0 .45 .45 0 0";1e-9>|/abs M[2]-0 0.45 0.45 0 0]
show["x FUZZY row4 = 0 .05 .05 0 0";1e-9>|/abs M[3]-0 0.05 0.05 0 0]
M2:fuzzy[&;member[5;MuD];member[-50;MuN]]
show["min FUZZY rows3/4 = .5 .5 / .1 .1";1e-9>|/,/abs M2[2 3;1 2]-(0.5 0.5;0.1 0.1)]
show["RB0 control (N=-50,D=5) = 1";1=control[RB0;M]]
show["RB1 control (N=-50,D=5) = 0";0=control[RB1;M]]

/ ---------- 6. conveyor simulation ----------
/ Nd boxes wanted on the loop. Each step: random consumption 15..35, random
/ returns 0..10 (net ~20 drawn); steps 60-89 a demand surge adds 25 more.
/ When on, the box machine adds P boxes per step.
Nd:400; P:60; T:150
\r 1995
dem:(15+T _draw 21)-T _draw 11
dem:dem+25*(!T)_lin 60+!30     / _lin: is each t in 60..89?

/ state = (N; previous N; machine on?).  Decide from N and D, then boxes move.
step:{[ctl;st;d] s:ctl[st 0;(st 0)-st 1;st 2]; ((st 0)+(P*s)-d;st 0;s)}
run:{[ctl] 1_ (-150;-150;0) step[ctl]\ dem}   / start 150 boxes short

/ ---------- 7. report + ASCII plot ----------
summary:{[name;r] n:r[;0]; s:r[;2]
 `0: name,"\n"
 `0: "  mean |dev|  ",(fmt(+/abs n)%1.0*#n),"\n"
 `0: "  max  |dev|  ",($|/abs n),"   (after warm-up t>=20: ",($|/abs 20_ n),")\n"
 `0: "  switches    ",($+/~(1_ s)=-1_ s),"\n"
 `0: "  time on     ",(fmt 100*(+/s)%1.0*#s),"%\n"}

/ one column = mean of 3 steps; rows every 40 boxes from +200 to -200;
/ '-' marks the target.  Bottom row: how many of the 3 steps the machine was on.
/ The plot is drawn with top-level statements rather than one big function:
/ the Dec 2021 Kona package (Termux kona/stable) throws spurious rank/type
/ errors when a function holds several each-results in locals.
chunks:{(3*!_(#x)%3)_ x}           / cut a run into chunks of 3 states
mean0:{(+/x[;0])%1.0*#x}           / mean N of a chunk
sum2:{+/{x 2}'x}                   / steps the machine was on in a chunk
snap:{40*_ 0.5+(-5|5&x%40)}        / snap a mean to the nearest row
lv:40*5-!11                        / row levels
lab:5$'$lv                         / row labels
cells:{[b;v] g:v=b; " *-"@g+2*(v=0)&~g}

F:run[fz]; H:run[th]; F50:run[fz50]
`0: "\n== conveyor: target Nd=",($Nd),", machine adds P=",($P),"/step, ",($T)," steps ==\n"
summary["fuzzy (paper rules)";F]
summary["naive threshold (on iff N<0)";H]
summary["fuzzy, aimed 50 boxes higher";F50]

pc:chunks F
pb:snap[mean0'pc]
pk:sum2'pc
`0: "\nfuzzy  (N = Nc-Nd, one column = 3 steps)\n"
rows:{cells[pb;x]}'lv
`0: lab,'" |",/:rows
`0: "   on |",(" .:#"@pk),"\n"
`0: "      |",(20#" "),"^surge^^^^",(20#" "),"t=150\n"

pc:chunks H
pb:snap[mean0'pc]
pk:sum2'pc
`0: "\nthreshold  (N = Nc-Nd, one column = 3 steps)\n"
rows:{cells[pb;x]}'lv
`0: lab,'" |",/:rows
`0: "   on |",(" .:#"@pk),"\n"
`0: "      |",(20#" "),"^surge^^^^",(20#" "),"t=150\n"
\\
