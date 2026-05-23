class Halt(Exception):
    pass


NIL = None


def is_atom(x):
    return isinstance(x, str) or x is NIL


class ChaitinMachine:
    def __init__(self, program, num_registers=8):
        # Registers R1..Rn
        self.reg = {f"R{i}": NIL for i in range(1, num_registers + 1)}
        self.reg["R1"] = program  # entire program in R1

    def eval(self, expr):
        # Atoms
        if is_atom(expr):
            if isinstance(expr, str) and expr.startswith("R"):
                return self.reg[expr]
            return expr

        if not isinstance(expr, list):
            raise ValueError(f"Bad expression: {expr}")

        op = expr[0]

        # SET
        if op == "SET":
            _, r, e = expr
            v = self.eval(e)
            self.reg[r] = v
            return v

        # SEQ
        if op == "SEQ":
            _, e1, e2 = expr
            self.eval(e1)
            return self.eval(e2)

        # IF
        if op == "IF":
            _, test, then, els = expr
            cond = self.eval(test)
            if cond is NIL:
                return self.eval(els)
            else:
                return self.eval(then)

        # CONS
        if op == "CONS":
            _, a, b = expr
            return [self.eval(a), self.eval(b)]

        # CAR
        if op == "CAR":
            _, e = expr
            v = self.eval(e)
            return NIL if v is NIL else v[0]

        # CDR
        if op == "CDR":
            _, e = expr
            v = self.eval(e)
            return NIL if v is NIL else v[1]

        # HALT
        if op == "HALT":
            raise Halt()

        raise ValueError(f"Unknown operator: {op}")

    def run(self):
        try:
            self.eval(self.reg["R1"])
        except Halt:
            pass
        return self.reg