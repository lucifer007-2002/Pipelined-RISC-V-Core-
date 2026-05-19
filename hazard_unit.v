`timescale 1ns / 1ps
//------------------------------------------------------------
// hazard_unit.v
// Detects pipeline hazards and generates stall/flush controls
// PURELY COMBINATIONAL
//
// Load-use hazard:
//   Cycle N:   LW  x1, 0(x2)       ← in EX, mem_read=1
//   Cycle N+1: ADD x3, x1, x4      ← in ID, reads x1
//   → x1 won't be in EX/MEM until end of cycle N
//   → ADD's EX stage would need it at START of cycle N+1
//   → Forwarding cannot bridge this — 1 cycle stall required
//
// What a stall does:
//   - Freezes PC (stall_if=1): IF fetches same instruction again
//   - Freezes IF/ID register (stall_if=1): holds current ID instr
//   - Injects NOP bubble into ID/EX register (flush_ex=1)
//   - The hazardous load stays in EX for one extra cycle
//   - After stall: MEM-EX forwarding resolves the dependency
//
// Control hazard (branch/jump flush):
//   Resolved in EX stage — 2 instructions already fetched must
//   be squashed. branch_flush signal from EX stage handles this.
//   This unit does NOT manage branch flushing — EX stage does.
//------------------------------------------------------------
module hazard_unit (
    // Instruction in ID stage (the one that wants to read)
    input  wire [4:0]  id_rs1_addr,
    input  wire [4:0]  id_rs2_addr,

    // Instruction in EX stage (the load that hasn't returned yet)
    input  wire [4:0]  ex_rd_addr,
    input  wire        ex_mem_read,       // 1 = load instruction in EX

    // Stall and flush outputs
    output wire        stall_if,          // 1 = freeze PC and IF/ID register
    output wire        stall_id,          // 1 = freeze ID/EX register (same as stall_if)
    output wire        flush_ex           // 1 = insert NOP bubble into ID/EX
);

    // Load-use hazard condition:
    // The instruction in EX is a load AND its destination
    // matches either source register of the instruction in ID
    wire load_use_hazard =
        ex_mem_read &&
        (ex_rd_addr != 5'b0) &&
        ((ex_rd_addr == id_rs1_addr) ||
         (ex_rd_addr == id_rs2_addr));

    // When load-use hazard detected:
    //   stall_if = 1: PC freezes, IF/ID register freezes
    //   stall_id = 1: ID/EX register freezes (holds the dependent instr)
    //   flush_ex = 1: EX stage gets a NOP bubble injected
    assign stall_if = load_use_hazard;
    assign stall_id = load_use_hazard;
    assign flush_ex = load_use_hazard;

endmodule
