`timescale 1ns / 1ps
//------------------------------------------------------------
// regfile_bram.v
// 32x32-bit register file — structured for BRAM inference
//
// BRAM inference rules Vivado requires:
//   1. Synchronous (clocked) reads — no async read ports
//   2. Single clock domain
//   3. Read and write use the same clock edge
//
// RV32I requirement: x0 is hardwired to 0. Handle in read logic.
//
// TWO READ PORTS: Vivado infers this as two separate BRAMs
// (each BRAM has 1 read + 1 write port). That's expected and
// correct — do not try to share one BRAM for two reads.
//
// WRITE-FIRST vs READ-FIRST: Use READ_FIRST (registered read
// returns old data). The WB forwarding in hazard handling
// takes care of the one-cycle write latency — don't shortcut
// this with bypass logic here, it breaks BRAM inference.
//------------------------------------------------------------
module regfile_bram (
    input  wire        clk,

    // Read port A (rs1)
    input  wire [4:0]  ra1,
    output reg  [31:0] rd1,     // registered — 1-cycle latency

    // Read port B (rs2)
    input  wire [4:0]  ra2,
    output reg  [31:0] rd2,     // registered — 1-cycle latency

    // Write port (from WB stage)
    input  wire [4:0]  wa,
    input  wire [31:0] wd,
    input  wire        we         // write enable
);

    // Memory array — synthesis attribute forces BRAM
    (* ram_style = "block" *)
    reg [31:0] regs [0:31];

    // Initialize x0 (and optionally all regs for simulation cleanliness)
    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] = 32'h0;
    end

    // Synchronous write
    always @(posedge clk) begin
        if (we && wa != 5'b0)   // x0 is never written
            regs[wa] <= wd;
    end

    // Synchronous read — port A
    always @(posedge clk) begin
        if (ra1 == 5'b0)
            rd1 <= 32'h0;       // x0 always reads 0
        else
            rd1 <= regs[ra1];
    end

    // Synchronous read — port B
    always @(posedge clk) begin
        if (ra2 == 5'b0)
            rd2 <= 32'h0;
        else
            rd2 <= regs[ra2];
    end

endmodule
