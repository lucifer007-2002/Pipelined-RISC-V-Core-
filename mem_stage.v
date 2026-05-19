`timescale 1ns / 1ps
//------------------------------------------------------------
// mem_stage.v
// Memory access stage
// Instantiates data_mem, applies load sign/zero extension,
// drives MEM/WB pipeline register
//------------------------------------------------------------
module mem_stage (
    input  wire        clk,
    input  wire        rst,

    // ── From EX/MEM pipeline register ────────────────────────
    input  wire [31:0] ex_mem_alu_result,  // memory address (for loads/stores)
    input  wire [31:0] ex_mem_rs2_data,    // store data (forwarded rs2)
    input  wire [4:0]  ex_mem_rd_addr,
    input  wire [31:0] ex_mem_pc_plus4,
    input  wire        ex_mem_mem_read,
    input  wire        ex_mem_mem_write,
    input  wire [2:0]  ex_mem_mem_width,
    input  wire        ex_mem_reg_write,
    input  wire [1:0]  ex_mem_wb_sel,

    // ── MEM/WB pipeline register outputs ─────────────────────
    output reg  [31:0] mem_wb_alu_result,
    output reg  [31:0] mem_wb_mem_data,    // extended load data
    output reg  [31:0] mem_wb_pc_plus4,
    output reg  [4:0]  mem_wb_rd_addr,
    output reg         mem_wb_reg_write,
    output reg  [1:0]  mem_wb_wb_sel
);

    // ── Data memory instantiation ─────────────────────────────
    wire [31:0] raw_mem_data;   // full 32-bit word from BRAM

    data_mem u_dmem (
        .clk       (clk),
        .addr      (ex_mem_alu_result),
        .wdata     (ex_mem_rs2_data),
        .mem_read  (ex_mem_mem_read),
        .mem_write (ex_mem_mem_write),
        .mem_width (ex_mem_mem_width),
        .rdata     (raw_mem_data)
    );

    // ── Load data extension ───────────────────────────────────
    // Applied to raw_mem_data combinationally AFTER BRAM registered output.
    // byte_off tells us which byte/half within the word to extract.
    wire [1:0] byte_off = ex_mem_alu_result[1:0];

    // Extract the target byte from the 32-bit word
    wire [7:0] byte_data =
        (byte_off == 2'b00) ? raw_mem_data[7:0]   :
        (byte_off == 2'b01) ? raw_mem_data[15:8]  :
        (byte_off == 2'b10) ? raw_mem_data[23:16] :
                               raw_mem_data[31:24] ;

    // Extract the target half-word
    wire [15:0] half_data =
        (byte_off[1] == 1'b0) ? raw_mem_data[15:0] :
                                  raw_mem_data[31:16];

    // Extended (sign or zero) load result
    reg [31:0] ext_mem_data;
    always @(*) begin
        case (ex_mem_mem_width)
            3'b000: ext_mem_data = {{24{byte_data[7]}},  byte_data};       // LB  sign-extend
            3'b001: ext_mem_data = {{16{half_data[15]}}, half_data};       // LH  sign-extend
            3'b010: ext_mem_data = raw_mem_data;                           // LW  full word
            3'b100: ext_mem_data = {24'h0, byte_data};                     // LBU zero-extend
            3'b101: ext_mem_data = {16'h0, half_data};                     // LHU zero-extend
            default: ext_mem_data = raw_mem_data;
        endcase
    end

    // ── MEM/WB pipeline register ──────────────────────────────
    // NOTE: Because data_mem has 1-cycle read latency (BRAM registered),
    // raw_mem_data is already one cycle delayed relative to ex_mem signals.
    // The extension logic runs combinationally on that registered output.
    // So ext_mem_data is effectively valid at the same time as this
    // pipeline register latches — timing is correct as-is.
    //
    // DO NOT add an extra register stage here. You would introduce
    // a 2-cycle load latency and break the forwarding assumptions.
    always @(posedge clk) begin
        if (rst) begin
            mem_wb_alu_result <= 32'h0;
            mem_wb_mem_data   <= 32'h0;
            mem_wb_pc_plus4   <= 32'h0;
            mem_wb_rd_addr    <= 5'h0;
            mem_wb_reg_write  <= 1'b0;
            mem_wb_wb_sel     <= 2'b00;
        end else begin
            mem_wb_alu_result <= ex_mem_alu_result;
            mem_wb_mem_data   <= ext_mem_data;
            mem_wb_pc_plus4   <= ex_mem_pc_plus4;
            mem_wb_rd_addr    <= ex_mem_rd_addr;
            mem_wb_reg_write  <= ex_mem_reg_write;
            mem_wb_wb_sel     <= ex_mem_wb_sel;
        end
    end

endmodule
