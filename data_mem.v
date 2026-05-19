`timescale 1ns / 1ps
//------------------------------------------------------------
// data_mem.v
// Synchronous data memory — BRAM inferred
// Supports byte (SB/LB), half-word (SH/LH), word (SW/LW)
//
// mem_width encoding (matches funct3 from RV32I):
//   3'b000 = byte   (LB  / SB)
//   3'b001 = half   (LH  / SH)
//   3'b010 = word   (LW  / SW)
//   3'b100 = byte   unsigned (LBU)
//   3'b101 = half   unsigned (LHU)
//
// BRAM is word-addressed internally (32-bit words).
// Byte address from ALU result is converted: addr[31:2] = word index,
// addr[1:0] = byte offset within word.
//
// Store byte-enables prevent corrupting adjacent bytes.
// This is the #1 source of silent memory bugs in student pipelines.
//------------------------------------------------------------
module data_mem #(
    parameter DEPTH = 1024      // 4KB = 1024 × 32-bit words
)(
    input  wire        clk,
    input  wire [31:0] addr,         // byte address from ALU result
    input  wire [31:0] wdata,        // data to write (from rs2, forwarded)
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [2:0]  mem_width,

    output reg  [31:0] rdata         // registered read data (1-cycle latency)
);

    (* ram_style = "block" *)
    reg [31:0] mem [0:DEPTH-1];

    // ── Write path — byte-enable masked ──────────────────────
    // word index and byte offset
    wire [29:0] word_addr  = addr[31:2];
    wire [1:0]  byte_off   = addr[1:0];

    always @(posedge clk) begin
        if (mem_write) begin
            case (mem_width)

                3'b010: begin // SW — write full word
                    mem[word_addr] <= wdata;
                end

                3'b001: begin // SH — write 16 bits, preserve other 16
                    case (byte_off)
                        2'b00: mem[word_addr][15:0]  <= wdata[15:0];
                        2'b10: mem[word_addr][31:16] <= wdata[15:0];
                        // Unaligned half-word: undefined in RV32I base
                        // Do nothing for 2'b01 / 2'b11 — hardware need not handle
                        default: ; // unaligned — ignore (trap in real implementation)
                    endcase
                end

                3'b000: begin // SB — write 8 bits, preserve other 24
                    case (byte_off)
                        2'b00: mem[word_addr][7:0]   <= wdata[7:0];
                        2'b01: mem[word_addr][15:8]  <= wdata[7:0];
                        2'b10: mem[word_addr][23:16] <= wdata[7:0];
                        2'b11: mem[word_addr][31:24] <= wdata[7:0];
                    endcase
                end

                default: ; // undefined width — do nothing
            endcase
        end
    end

    // ── Read path — synchronous (BRAM registered output) ─────
    // Raw 32-bit word read. Extension (sign/zero) happens in MEM stage.
    always @(posedge clk) begin
        if (mem_read) begin
            rdata <= mem[word_addr];
        end
    end

endmodule
