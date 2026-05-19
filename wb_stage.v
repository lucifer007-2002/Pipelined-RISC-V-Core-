`timescale 1ns / 1ps
//------------------------------------------------------------
// wb_stage.v
// Writeback stage — combinational only
// Selects the correct data to write back to the register file
//
// wb_sel encoding:
//   2'b00 = ALU result    (R-type, I-type ALU, stores: nothing written)
//   2'b01 = memory data   (loads: LW, LH, LB, LHU, LBU)
//   2'b10 = PC+4          (JAL, JALR: link address saved to rd)
//------------------------------------------------------------
module wb_stage (
    // From MEM/WB pipeline register
    input  wire [31:0] mem_wb_alu_result,
    input  wire [31:0] mem_wb_mem_data,
    input  wire [31:0] mem_wb_pc_plus4,
    input  wire [1:0]  mem_wb_wb_sel,
    input  wire [4:0]  mem_wb_rd_addr,
    input  wire        mem_wb_reg_write,

    // To register file write port (back to ID stage)
    output wire [31:0] wb_data,
    output wire [4:0]  wb_rd,
    output wire        wb_reg_write
);

    // WB mux — picks which result goes to register file
    assign wb_data = (mem_wb_wb_sel == 2'b01) ? mem_wb_mem_data   :
                     (mem_wb_wb_sel == 2'b10) ? mem_wb_pc_plus4   :
                                                 mem_wb_alu_result ;

    // Pass-through destination register and write enable
    assign wb_rd        = mem_wb_rd_addr;
    assign wb_reg_write = mem_wb_reg_write;

endmodule
