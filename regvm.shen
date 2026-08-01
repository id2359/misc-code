\\ regvm.shen -- A small register-machine VM in Shen
\\
\\ Design goals:
\\ - Tiny core (pc, regs, mem, prog, halted?)
\\ - Label-aware assembler to numeric PCs
\\ - Deterministic step/run with optional tracing
\\
\\ State representation:
\\   [state PC REGS MEM PROG HALTED]
\\   where REGS is an assoc list [(@p r0 0) (@p r1 42) ...]
\\         MEM  is an assoc list [(@p 0 123) (@p 1 999) ...]
\\         PROG is a vector/list of instructions

(datatype rm

  ______________________________
  (value *rm-trace?*) : boolean;

  ___________________________
  (value *rm-step-limit*) : number;)

(define rm-defaults
  -> (do (set *rm-trace?* false)
         (set *rm-step-limit* 100000)
         set))

(rm-defaults)

\\ ----------------------- assoc utilities -----------------------

(define rm-lookup
  {A --> (list (A * B)) --> B --> B}
  _ [] Default -> Default
  K [(@p K V) | _] _ -> V
  K [_ | Rest] Default -> (rm-lookup K Rest Default))

(define rm-put
  {A --> B --> (list (A * B)) --> (list (A * B))}
  K V [] -> [(@p K V)]
  K V [(@p K _) | Rest] -> [(@p K V) | Rest]
  K V [Pair | Rest] -> [Pair | (rm-put K V Rest)])

(define rm-getreg
  {symbol --> (list (symbol * number)) --> number}
  R Regs -> (rm-lookup R Regs 0))

(define rm-setreg
  {symbol --> number --> (list (symbol * number)) --> (list (symbol * number))}
  R V Regs -> (rm-put R V Regs))

(define rm-getmem
  {number --> (list (number * number)) --> number}
  A Mem -> (rm-lookup A Mem 0))

(define rm-setmem
  {number --> number --> (list (number * number)) --> (list (number * number))}
  A V Mem -> (rm-put A V Mem))

\\ ----------------------- instruction format -----------------------
\\
\\ Instructions are plain lists:
\\   [const R N]
\\   [mov RD RS]
\\   [add RD RA RB]
\\   [sub RD RA RB]
\\   [mul RD RA RB]
\\   [load RD RA]     ; RD := mem[ regs[RA] ]
\\   [store RS RA]    ; mem[ regs[RA] ] := regs[RS]
\\   [jmp PC]
\\   [jz R PC]
\\   [jnz R PC]
\\   [halt]
\\
\\ Assembler input additionally supports:
\\   [label L]
\\ and jump targets may be symbols (labels) which are resolved to PCs.

(define rm-halted?
  {[state number A B C boolean] --> boolean}
  [state _ _ _ _ Halted] -> Halted)

(define rm-mk
  {(list (list A)) --> (list (symbol * number)) --> (list (number * number)) --> (list A)}
  Prog Regs Mem -> [state 0 Regs Mem Prog false])

(define rm-fetch
  {[state number A B (list (list A)) boolean] --> (list A)}
  [state PC _ _ Prog _] -> (nth PC Prog))

(define nth
  {number --> (list A) --> A}
  0 [X | _] -> X
  N [_ | Xs] -> (nth (- N 1) Xs))

(define rm-trace
  {string --> A}
  _ -> skip where (not (value *rm-trace?*))
  S -> (output "~A~%" S))

(define rm-step
  {[state number (list (symbol * number)) (list (number * number)) (list (list A)) boolean] --> (list A)}
  [state PC Regs Mem Prog true] -> [state PC Regs Mem Prog true]
  [state PC Regs Mem Prog false]
    -> (let Instr (nth PC Prog)
         (let _ (rm-trace (make-string "pc=~A instr=~R" PC Instr))
         (rm-exec Instr [state PC Regs Mem Prog false]))))

(define rm-exec
  {(list A) --> (list A) --> (list A)}

  [halt] [state PC Regs Mem Prog _]
    -> [state PC Regs Mem Prog true]

  [const R N] [state PC Regs Mem Prog _]
    -> [state (+ PC 1) (rm-setreg R N Regs) Mem Prog false]

  [mov RD RS] [state PC Regs Mem Prog _]
    -> (let V (rm-getreg RS Regs)
         [state (+ PC 1) (rm-setreg RD V Regs) Mem Prog false])

  [add RD RA RB] [state PC Regs Mem Prog _]
    -> (let A (rm-getreg RA Regs)
         (let B (rm-getreg RB Regs)
           [state (+ PC 1) (rm-setreg RD (+ A B) Regs) Mem Prog false]))

  [sub RD RA RB] [state PC Regs Mem Prog _]
    -> (let A (rm-getreg RA Regs)
         (let B (rm-getreg RB Regs)
           [state (+ PC 1) (rm-setreg RD (- A B) Regs) Mem Prog false]))

  [mul RD RA RB] [state PC Regs Mem Prog _]
    -> (let A (rm-getreg RA Regs)
         (let B (rm-getreg RB Regs)
           [state (+ PC 1) (rm-setreg RD (* A B) Regs) Mem Prog false]))

  [load RD RA] [state PC Regs Mem Prog _]
    -> (let Addr (rm-getreg RA Regs)
         (let V (rm-getmem Addr Mem)
           [state (+ PC 1) (rm-setreg RD V Regs) Mem Prog false]))

  [store RS RA] [state PC Regs Mem Prog _]
    -> (let Addr (rm-getreg RA Regs)
         (let V (rm-getreg RS Regs)
           [state (+ PC 1) Regs (rm-setmem Addr V Mem) Prog false]))

  [jmp Target] [state _ Regs Mem Prog _]
    -> [state Target Regs Mem Prog false]

  [jz R Target] [state PC Regs Mem Prog _]
    -> (if (= 0 (rm-getreg R Regs))
           [state Target Regs Mem Prog false]
           [state (+ PC 1) Regs Mem Prog false])

  [jnz R Target] [state PC Regs Mem Prog _]
    -> (if (not (= 0 (rm-getreg R Regs)))
           [state Target Regs Mem Prog false]
           [state (+ PC 1) Regs Mem Prog false])

  Instr State
    -> (error (make-string "rm-exec: unknown instruction ~R" Instr)))

(define rm-run
  {(list A) --> (list A)}
  State -> (rm-run* State 0 (value *rm-step-limit*)))

(define rm-run*
  {(list A) --> number --> number --> (list A)}
  State Steps Max -> State where (rm-halted? State)
  State Steps Max -> (error "rm-run: step limit reached") where (>= Steps Max)
  State Steps Max -> (rm-run* (rm-step State) (+ Steps 1) Max))

(define rm-regs
  {[state number A B C boolean] --> A}
  [state _ Regs _ _ _] -> Regs)

(define rm-mem
  {[state number A B C boolean] --> B}
  [state _ _ Mem _ _] -> Mem)

\\ ----------------------- assembler -----------------------

(define rm-assemble
  {(list (list A)) --> (list (list A))}
  Forms -> (let Labels (rm-pass-labels Forms 0 [])
             (rm-pass-resolve Forms Labels [])))

(define rm-pass-labels
  {(list (list A)) --> number --> (list (symbol * number)) --> (list (symbol * number))}
  [] _ Acc -> Acc
  [[label L] | Rest] PC Acc -> (rm-pass-labels Rest PC (rm-put L PC Acc))
  [_ | Rest] PC Acc -> (rm-pass-labels Rest (+ PC 1) Acc))

(define rm-pass-resolve
  {(list (list A)) --> (list (symbol * number)) --> (list (list A)) --> (list (list A))}
  [] _ Acc -> (reverse Acc)
  [[label _] | Rest] Labels Acc -> (rm-pass-resolve Rest Labels Acc)
  [Instr | Rest] Labels Acc -> (rm-pass-resolve Rest Labels [(rm-resolve-instr Instr Labels) | Acc]))

(define rm-resolve-instr
  {(list A) --> (list (symbol * number)) --> (list A)}
  [jmp L] Labels -> [jmp (rm-lookup L Labels (error (make-string "unknown label ~A" L)))] where (symbol? L)
  [jz R L] Labels -> [jz R (rm-lookup L Labels (error (make-string "unknown label ~A" L)))] where (symbol? L)
  [jnz R L] Labels -> [jnz R (rm-lookup L Labels (error (make-string "unknown label ~A" L)))] where (symbol? L)
  X _ -> X)

\\ ----------------------- example program -----------------------
\\ Sum 1..N into r1 (N in r0). Uses r2 as 1.
\\
\\ (define sum-prog
\\   -> (rm-assemble
\\        [[const r1 0]
\\         [const r2 1]
\\         [label loop]
\\         [jz r0 done]
\\         [add r1 r1 r0]
\\         [sub r0 r0 r2]
\\         [jmp loop]
\\         [label done]
\\         [halt]]))
\\
\\ (define demo
\\   N -> (let P (sum-prog)
\\          (let S (rm-mk P [(@p r0 N)] [])
\\            (rm-regs (rm-run S)))) )
