`timescale 1ns / 1ps
//------------------------------------------------------------
// forwarding_unit.v
// Detects data hazards and generates forwarding mux selects
// PURELY COMBINATIONAL — no clock port
//
// fwd_a / fwd_b encoding:
//   2'b00 = no forward  → use ID/EX register value (normal)
//   2'b01 = MEM forward → use EX/MEM alu_result
//   2'b10 = WB  forward → use MEM/WB wb_data
//
// Three forwarding cases covered:
//   EX-EX:  instr in EX needs result of instr currently in MEM
//   MEM-EX: instr in EX needs result of instr currently in WB
//   WB-EX:  instr in EX needs result being written by WB this cycle
//           (only needed because BRAM regfile has 1-cycle read latency)
//
// PRIORITY RULE — critical:
//   EX/MEM case must be checked BEFORE MEM/WB case.
//   Example: two consecutive writes to x1 — if MEM/WB case fires
//   before EX/MEM, you forward the older stale value. Always
//   prefer the most recently produced result.
//------------------------------------------------------------
module forwarding_unit (
    // Addresses of source registers in EX stage
    input  wire [4:0]  ex_rs1_addr,
    input  wire [4:0]  ex_rs2_addr,

    // EX/MEM pipeline register — result of instruction 1 cycle ahead
    input  wire [4:0]  ex_mem_rd,
    input  wire        ex_mem_reg_write,

    // MEM/WB pipeline register — result of instruction 2 cycles ahead
    input  wire [4:0]  mem_wb_rd,
    input  wire        mem_wb_reg_write,

    // Forwarding mux selects (to EX stage)
    output reg  [1:0]  fwd_a,
    output reg  [1:0]  fwd_b
);

    always @(*) begin
        // ── Forward A (rs1 source) ──────────────────────────────
        // Default: no forwarding
        fwd_a = 2'b00;

        // EX-EX forward: instruction ahead (now in MEM) wrote
        // to a register that this instruction reads as rs1
        if (ex_mem_reg_write &&
            (ex_mem_rd != 5'b0) &&          // never forward x0
            (ex_mem_rd == ex_rs1_addr)) begin
            fwd_a = 2'b01;                  // take from EX/MEM.alu_result

        // MEM-EX forward: instruction 2 ahead (now in WB) wrote
        // to rs1. Only fires when EX-EX case did NOT fire (priority).
        end else if (mem_wb_reg_write &&
                     (mem_wb_rd != 5'b0) &&
                     (mem_wb_rd == ex_rs1_addr)) begin
            fwd_a = 2'b10;                  // take from MEM/WB.wb_data
        end

        // ── Forward B (rs2 source) ──────────────────────────────
        fwd_b = 2'b00;

        if (ex_mem_reg_write &&
            (ex_mem_rd != 5'b0) &&
            (ex_mem_rd == ex_rs2_addr)) begin
            fwd_b = 2'b01;

        end else if (mem_wb_reg_write &&
                     (mem_wb_rd != 5'b0) &&
                     (mem_wb_rd == ex_rs2_addr)) begin
            fwd_b = 2'b10;
        end
    end

endmodule
