const std = @import("std");

const MemorySize = 1024;
const NumRegisters = 4;

const Opcode = enum(u8) {
    halt = 0,      // Halt execution (1 byte)
    load = 1,      // LOAD reg, imm: r[reg] = imm (3 bytes: opcode, reg, imm)
    add = 2,       // ADD reg1, reg2: r[reg1] += r[reg2] (3 bytes: opcode, reg1, reg2)
    sub = 3,       // SUB reg1, reg2: r[reg1] -= r[reg2] (3 bytes: opcode, reg1, reg2)
    jmp = 4,       // JMP addr: pc = addr (3 bytes: opcode, addr_low, addr_high)
    jz = 5,        // JZ reg, addr: if r[reg] == 0, pc = addr (4 bytes: opcode, reg, addr_low, addr_high)
    store = 6,     // STORE reg, addr: memory[addr] = r[reg] (4 bytes: opcode, reg, addr_low, addr_high)
    loadm = 7,     // LOADM reg, addr: r[reg] = memory[addr] (4 bytes: opcode, reg, addr_low, addr_high)
    push = 8,      // PUSH reg: memory[sp] = r[reg]; sp -= 1 (2 bytes: opcode, reg)
    pop = 9,       // POP reg: sp += 1; r[reg] = memory[sp] (2 bytes: opcode, reg)
};

const VM = struct {
    memory: [MemorySize]u8,
    registers: [NumRegisters]u8,
    pc: usize,
    sp: usize,

    pub fn init() VM {
        return .{
            .memory = [_]u8{0} ** MemorySize,
            .registers = [_]u8{0} ** NumRegisters,
            .pc = 4000,
            .sp = MemorySize - 1,
        };
    }

    pub fn loadProgram(self: *VM, program: []const u8, start_addr: usize) !void {
        if (start_addr + program.len > MemorySize) {
            return error.OutOfMemory;
        }
        @memcpy(self.memory[start_addr..start_addr + program.len], program);
    }

    pub fn run(self: *VM) !void {
        while (true) {
            if (self.pc >= MemorySize) {
                return error.InvalidPC;
            }
            const opcode_byte = self.memory[self.pc];
            self.pc += 1;
   
            const opcode: Opcode = @enumFromInt(opcode_byte);

            switch (opcode) {
                .halt => return,
                .load => {
                    if (self.pc + 1 >= MemorySize) return error.InvalidInstruction;
                    const reg = self.memory[self.pc];
                    self.pc += 1;
                    const imm = self.memory[self.pc];
                    self.pc += 1;
                    if (reg >= NumRegisters) return error.InvalidRegister;
                    self.registers[reg] = imm;
                },
                .add => {
                    if (self.pc + 1 >= MemorySize) return error.InvalidInstruction;
                    const reg1 = self.memory[self.pc];
                    self.pc += 1;
                    const reg2 = self.memory[self.pc];
                    self.pc += 1;
                    if (reg1 >= NumRegisters or reg2 >= NumRegisters) return error.InvalidRegister;
                    self.registers[reg1] +%= self.registers[reg2]; // Wrapping add
                },
                .sub => {
                    if (self.pc + 1 >= MemorySize) return error.InvalidInstruction;
                    const reg1 = self.memory[self.pc];
                    self.pc += 1;
                    const reg2 = self.memory[self.pc];
                    self.pc += 1;
                    if (reg1 >= NumRegisters or reg2 >= NumRegisters) return error.InvalidRegister;
                    self.registers[reg1] -%= self.registers[reg2]; // Wrapping sub
                },
                .jmp => {
                    if (self.pc + 1 >= MemorySize) return error.InvalidInstruction;
                    const addr_low = self.memory[self.pc];
                    self.pc += 1;
                    const addr_high = self.memory[self.pc];
                    self.pc += 1;
                    const addr = (@as(u16, addr_high) << 8) | addr_low;
                    if (addr >= MemorySize) return error.InvalidAddress;
                    self.pc = addr;
                },
                .jz => {
                    if (self.pc + 2 >= MemorySize) return error.InvalidInstruction;
                    const reg = self.memory[self.pc];
                    self.pc += 1;
                    const addr_low = self.memory[self.pc];
                    self.pc += 1;
                    const addr_high = self.memory[self.pc];
                    self.pc += 1;
                    if (reg >= NumRegisters) return error.InvalidRegister;
                    const addr = (@as(u16, addr_high) << 8) | addr_low;
                    if (addr >= MemorySize) return error.InvalidAddress;
                    if (self.registers[reg] == 0) {
                        self.pc = addr;
                    }
                },
                .store => {
                    if (self.pc + 2 >= MemorySize) return error.InvalidInstruction;
                    const reg = self.memory[self.pc];
                    self.pc += 1;
                    const addr_low = self.memory[self.pc];
                    self.pc += 1;
                    const addr_high = self.memory[self.pc];
                    self.pc += 1;
                    if (reg >= NumRegisters) return error.InvalidRegister;
                    const addr = (@as(u16, addr_high) << 8) | addr_low;
                    if (addr >= MemorySize) return error.InvalidAddress;
                    self.memory[addr] = self.registers[reg];
                },
                .loadm => {
                    if (self.pc + 2 >= MemorySize) return error.InvalidInstruction;
                    const reg = self.memory[self.pc];
                    self.pc += 1;
                    const addr_low = self.memory[self.pc];
                    self.pc += 1;
                    const addr_high = self.memory[self.pc];
                    self.pc += 1;
                    if (reg >= NumRegisters) return error.InvalidRegister;
                    const addr = (@as(u16, addr_high) << 8) | addr_low;
                    if (addr >= MemorySize) return error.InvalidAddress;
                    self.registers[reg] = self.memory[addr];
                },
                .push => {
                    if (self.pc >= MemorySize) return error.InvalidInstruction;
                    const reg = self.memory[self.pc];
                    self.pc += 1;
                    if (reg >= NumRegisters) return error.InvalidRegister;
                    if (self.sp == 0) return error.StackOverflow;
                    self.memory[self.sp] = self.registers[reg];
                    self.sp -= 1;
                },
                .pop => {
                    if (self.pc >= MemorySize) return error.InvalidInstruction;
                    const reg = self.memory[self.pc];
                    self.pc += 1;
                    if (reg >= NumRegisters) return error.InvalidRegister;
                    if (self.sp >= MemorySize - 1) return error.StackUnderflow;
                    self.sp += 1;
                    self.registers[reg] = self.memory[self.sp];
                },
            }
        }
    }
};

pub fn main() !void {
    var vm = VM.init();

    // Sample program: Load 5 into r0, 3 into r1, add r0 + r1 into r0, store r0 at address 0x0100, halt.
    // Bytecode: LOAD r0,5 (01 00 05), LOAD r1,3 (01 01 03), ADD r0,r1 (02 00 01), STORE r0,0x0100 (06 00 00 01), HALT (00)
    const program = [_]u8{ 0x01, 0x00, 0x05, 0x01, 0x01, 0x03, 0x02, 0x00, 0x01, 0x06, 0x00, 0x00, 0x01, 0x00 };
    try vm.loadProgram(&program, 0);
    try vm.run();

    // Output result using the new I/O interface
    var buffer: [1024]u8 = undefined;  // Allocate a buffer for buffered writing
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    const stdout: *std.Io.Writer = &stdout_writer.interface;

    try stdout.print("Result at 0x0100: {d}\n", .{vm.memory[0x0100]});
    try stdout.flush();  // Important: flush to ensure output appears
}
