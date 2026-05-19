`timescale 1ns / 1ps
//------------------------------------------------------------
// instr_mem.v
// Synchronous instruction memory — BRAM inferred
// 1-cycle read latency (registered output)
// Depth: 1024 words = 4KB program space
//------------------------------------------------------------
module instr_mem #(
    parameter DEPTH = 1024          // number of 32-bit words
)(
    input  wire        clk,
    input  wire [31:0] addr,         // byte address from PC
    output reg  [31:0] instr         // registered output — 1-cycle latency
);
    // Memory array
    // (* rom_style = "block" *) forces BRAM inference if Vivado
    // tries to use distributed RAM. Uncomment if needed.
    (* rom_style = "block" *)
    reg [31:0] mem [0:DEPTH-1];

    // Load program at simulation time
    initial begin
        $readmemh("test_programs/test1.mem", mem);
    end

    // Synchronous read — this is what makes Vivado infer BRAM
    // DO NOT make this combinational (async). BRAM has registered outputs.
    always @(posedge clk) begin
        instr <= mem[addr[31:2]];   // word-aligned: drop bottom 2 bits
    end

endmodule
