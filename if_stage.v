`timescale 1ns / 1ps
//------------------------------------------------------------
// if_stage.v
// Instruction Fetch stage
// Manages PC, drives instruction memory, handles:
//   - stall (freeze PC)
//   - branch taken / jump (redirect PC)
//   - flush (convert fetched instr to NOP via valid flag)
//------------------------------------------------------------
module if_stage (
    input  wire        clk,
    input  wire        rst,

    // Hazard unit controls
    input  wire        stall,          // hold PC — do not advance
    input  wire        flush,          // squash fetched instruction (branch mispredict)

    // Branch/jump redirect from EX stage
    input  wire        branch_taken,   // asserted when branch resolves as taken
    input  wire [31:0] branch_target,  // target PC for taken branch or jump

    // To IF/ID pipeline register
    output reg  [31:0] if_pc,          // PC of current instruction
    output reg  [31:0] if_pc_plus4,    // PC+4 (needed for JAL/JALR link address)
    output wire [31:0] if_instr,       // instruction (from memory — 1-cycle latency)
    output reg         if_valid        // 0 = bubble/NOP, 1 = real instruction
);

    // ── PC register ──────────────────────────────────────────
    reg  [31:0] pc;
    wire [31:0] pc_next;

    // PC mux: branch/jump target overrides sequential PC+4
    assign pc_next = branch_taken ? branch_target : (pc + 32'd4);

    always @(posedge clk) begin
        if (rst) begin
            pc <= 32'h0000_0000;     // reset vector — change if your design needs it
        end else if (!stall) begin
            pc <= pc_next;
        end
        // if stall: PC holds its value, memory sees same address again
    end

    // ── Drive instruction memory ──────────────────────────────
    // instr_mem is instantiated in riscv_top.v and its output
    // is passed back in as if_instr. We expose the PC to it.
    // The output wire if_instr connects to instr_mem's registered output.
    // (instr_mem instantiated at top level — see riscv_top.v)
    assign if_instr = if_instr;     // driven from top-level connection

    // ── IF/ID pipeline register update ───────────────────────
    always @(posedge clk) begin
        if (rst || flush) begin
            if_pc       <= 32'h0;
            if_pc_plus4 <= 32'h0;
            if_valid    <= 1'b0;    // inject bubble
        end else if (!stall) begin
            if_pc       <= pc;
            if_pc_plus4 <= pc + 32'd4;
            if_valid    <= 1'b1;
        end
        // stall: pipeline register freezes — holds current values
    end

endmodule
