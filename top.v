`timescale 1ns / 1ps
//------------------------------------------------------------
// riscv_top.v  — Full 5-stage RV32I pipeline top-level
// Target: Artix-7 xc7a35tcsg324-1
//------------------------------------------------------------
module riscv_top (
    input  wire        clk,
    input  wire        rst,
    // Debug ports (for testbench observation)
    output wire [31:0] dbg_pc,
    output wire [31:0] dbg_instr,
    output wire [31:0] dbg_wb_data,
    output wire [4:0]  dbg_wb_rd
);

    //=========================================================
    // SECTION 1 — IF stage wires
    //=========================================================
    wire [31:0] if_pc, if_pc_plus4, if_instr;
    wire        if_valid;

    //=========================================================
    // SECTION 2 — IF/ID register (inside if_stage)
    // Wires are outputs of if_stage, inputs to id_stage
    //=========================================================
    // (Named if_pc, if_pc_plus4, if_instr, if_valid from if_stage)

    //=========================================================
    // SECTION 3 — ID stage wires
    //=========================================================
    // ID/EX pipeline register outputs
    wire [31:0] id_ex_pc, id_ex_pc_plus4;
    wire [31:0] id_ex_rs1_data, id_ex_rs2_data;
    wire [31:0] id_ex_imm;
    wire [4:0]  id_ex_rs1_addr, id_ex_rs2_addr, id_ex_rd_addr;
    wire [2:0]  id_ex_funct3;
    wire [3:0]  id_ex_alu_op;
    wire        id_ex_alu_src;
    wire        id_ex_mem_read, id_ex_mem_write;
    wire [2:0]  id_ex_mem_width;
    wire        id_ex_reg_write;
    wire [1:0]  id_ex_wb_sel;
    wire        id_ex_branch, id_ex_jump, id_ex_jump_jalr;
    // Combinational decode outputs (for hazard unit)
    wire [4:0]  id_rs1_addr, id_rs2_addr;

    //=========================================================
    // SECTION 4 — EX stage wires
    //=========================================================
    wire        branch_taken;
    wire [31:0] branch_target;
    // EX/MEM pipeline register outputs
    wire [31:0] ex_mem_alu_result;
    wire [31:0] ex_mem_rs2_data;
    wire [4:0]  ex_mem_rd_addr;
    wire [31:0] ex_mem_pc_plus4;
    wire        ex_mem_mem_read, ex_mem_mem_write;
    wire [2:0]  ex_mem_mem_width;
    wire        ex_mem_reg_write;
    wire [1:0]  ex_mem_wb_sel;

    //=========================================================
    // SECTION 5 — MEM stage wires
    //=========================================================
    // MEM/WB pipeline register outputs
    wire [31:0] mem_wb_alu_result;
    wire [31:0] mem_wb_mem_data;
    wire [31:0] mem_wb_pc_plus4;
    wire [4:0]  mem_wb_rd_addr;
    wire        mem_wb_reg_write;
    wire [1:0]  mem_wb_wb_sel;

    //=========================================================
    // SECTION 6 — WB stage wires
    //=========================================================
    wire [31:0] wb_data;
    wire [4:0]  wb_rd;
    wire        wb_reg_write;

    //=========================================================
    // SECTION 7 — Hazard and forwarding control wires
    //=========================================================
    wire        stall_if, stall_id, flush_ex_ldu;
    wire [1:0]  fwd_a, fwd_b;

    // Combined flush signals:
    // flush_if_id: branch taken OR load-use stall (both squash IF/ID)
    // flush_ex:    branch taken (squash what's in ID→EX) OR load-use stall NOP
    wire flush_if_id = branch_taken | stall_if;
    wire flush_ex    = branch_taken | flush_ex_ldu;

    //=========================================================
    // SECTION 8 — Instruction memory
    //=========================================================
    wire [31:0] imem_instr;

    instr_mem #(.DEPTH(1024)) u_imem (
        .clk  (clk),
        .addr (if_pc),
        .instr(imem_instr)
    );

    //=========================================================
    // SECTION 9 — IF stage
    //=========================================================
    if_stage u_if (
        .clk           (clk),
        .rst           (rst),
        .stall         (stall_if),
        .flush         (flush_if_id),
        .branch_taken  (branch_taken),
        .branch_target (branch_target),
        .if_pc         (if_pc),
        .if_pc_plus4   (if_pc_plus4),
        .if_instr      (imem_instr),     // fed from instr_mem
        .if_valid      (if_valid)
    );

    //=========================================================
    // SECTION 10 — ID stage
    //=========================================================
    id_stage u_id (
        .clk              (clk),
        .rst              (rst),
        .if_id_pc         (if_pc),
        .if_id_pc_plus4   (if_pc_plus4),
        .if_id_instr      (imem_instr),  // note: same-cycle instr from BRAM
        .if_id_valid      (if_valid),
        .stall            (stall_id),
        .flush            (flush_if_id),
        // WB writeback port
        .wb_rd            (wb_rd),
        .wb_data          (wb_data),
        .wb_reg_write     (wb_reg_write),
        // ID/EX outputs
        .id_ex_pc         (id_ex_pc),
        .id_ex_pc_plus4   (id_ex_pc_plus4),
        .id_ex_rs1_data   (id_ex_rs1_data),
        .id_ex_rs2_data   (id_ex_rs2_data),
        .id_ex_imm        (id_ex_imm),
        .id_ex_rs1_addr   (id_ex_rs1_addr),
        .id_ex_rs2_addr   (id_ex_rs2_addr),
        .id_ex_rd_addr    (id_ex_rd_addr),
        .id_ex_funct3     (id_ex_funct3),
        .id_ex_alu_op     (id_ex_alu_op),
        .id_ex_alu_src    (id_ex_alu_src),
        .id_ex_mem_read   (id_ex_mem_read),
        .id_ex_mem_write  (id_ex_mem_write),
        .id_ex_mem_width  (id_ex_mem_width),
        .id_ex_reg_write  (id_ex_reg_write),
        .id_ex_wb_sel     (id_ex_wb_sel),
        .id_ex_branch     (id_ex_branch),
        .id_ex_jump       (id_ex_jump),
        .id_ex_jump_jalr  (id_ex_jump_jalr),
        // Combinational addresses for hazard unit
        .id_rs1_addr      (id_rs1_addr),
        .id_rs2_addr      (id_rs2_addr)
    );

    //=========================================================
    // SECTION 11 — EX stage
    //=========================================================
    ex_stage u_ex (
        .clk                  (clk),
        .rst                  (rst),
        .id_ex_pc             (id_ex_pc),
        .id_ex_pc_plus4       (id_ex_pc_plus4),
        .id_ex_rs1_data       (id_ex_rs1_data),
        .id_ex_rs2_data       (id_ex_rs2_data),
        .id_ex_imm            (id_ex_imm),
        .id_ex_rs1_addr       (id_ex_rs1_addr),
        .id_ex_rs2_addr       (id_ex_rs2_addr),
        .id_ex_rd_addr        (id_ex_rd_addr),
        .id_ex_funct3         (id_ex_funct3),
        .id_ex_alu_op         (id_ex_alu_op),
        .id_ex_alu_src        (id_ex_alu_src),
        .id_ex_mem_read       (id_ex_mem_read),
        .id_ex_mem_write      (id_ex_mem_write),
        .id_ex_mem_width      (id_ex_mem_width),
        .id_ex_reg_write      (id_ex_reg_write),
        .id_ex_wb_sel         (id_ex_wb_sel),
        .id_ex_branch         (id_ex_branch),
        .id_ex_jump           (id_ex_jump),
        .id_ex_jump_jalr      (id_ex_jump_jalr),
        // Forwarding
        .fwd_a                (fwd_a),
        .fwd_b                (fwd_b),
        .ex_mem_alu_result    (ex_mem_alu_result),  // feedback for EX-EX fwd
        .mem_wb_wb_data       (wb_data),            // WB output for MEM-EX fwd
        .flush                (flush_ex),
        // Branch resolution
        .branch_taken         (branch_taken),
        .branch_target        (branch_target),
        // EX/MEM register outputs
        .ex_mem_alu_result_r  (ex_mem_alu_result),
        .ex_mem_rs2_data      (ex_mem_rs2_data),
        .ex_mem_rd_addr       (ex_mem_rd_addr),
        .ex_mem_pc_plus4      (ex_mem_pc_plus4),
        .ex_mem_mem_read      (ex_mem_mem_read),
        .ex_mem_mem_write     (ex_mem_mem_write),
        .ex_mem_mem_width     (ex_mem_mem_width),
        .ex_mem_reg_write     (ex_mem_reg_write),
        .ex_mem_wb_sel        (ex_mem_wb_sel)
    );

    //=========================================================
    // SECTION 12 — MEM stage
    //=========================================================
    mem_stage u_mem (
        .clk                (clk),
        .rst                (rst),
        .ex_mem_alu_result  (ex_mem_alu_result),
        .ex_mem_rs2_data    (ex_mem_rs2_data),
        .ex_mem_rd_addr     (ex_mem_rd_addr),
        .ex_mem_pc_plus4    (ex_mem_pc_plus4),
        .ex_mem_mem_read    (ex_mem_mem_read),
        .ex_mem_mem_write   (ex_mem_mem_write),
        .ex_mem_mem_width   (ex_mem_mem_width),
        .ex_mem_reg_write   (ex_mem_reg_write),
        .ex_mem_wb_sel      (ex_mem_wb_sel),
        // MEM/WB register outputs
        .mem_wb_alu_result  (mem_wb_alu_result),
        .mem_wb_mem_data    (mem_wb_mem_data),
        .mem_wb_pc_plus4    (mem_wb_pc_plus4),
        .mem_wb_rd_addr     (mem_wb_rd_addr),
        .mem_wb_reg_write   (mem_wb_reg_write),
        .mem_wb_wb_sel      (mem_wb_wb_sel)
    );

    //=========================================================
    // SECTION 13 — WB stage
    //=========================================================
    wb_stage u_wb (
        .mem_wb_alu_result (mem_wb_alu_result),
        .mem_wb_mem_data   (mem_wb_mem_data),
        .mem_wb_pc_plus4   (mem_wb_pc_plus4),
        .mem_wb_wb_sel     (mem_wb_wb_sel),
        .mem_wb_rd_addr    (mem_wb_rd_addr),
        .mem_wb_reg_write  (mem_wb_reg_write),
        .wb_data           (wb_data),
        .wb_rd             (wb_rd),
        .wb_reg_write      (wb_reg_write)
    );

    //=========================================================
    // SECTION 14 — Forwarding unit
    //=========================================================
    forwarding_unit u_fwd (
        .ex_rs1_addr      (id_ex_rs1_addr),
        .ex_rs2_addr      (id_ex_rs2_addr),
        .ex_mem_rd        (ex_mem_rd_addr),
        .ex_mem_reg_write (ex_mem_reg_write),
        .mem_wb_rd        (mem_wb_rd_addr),
        .mem_wb_reg_write (mem_wb_reg_write),
        .fwd_a            (fwd_a),
        .fwd_b            (fwd_b)
    );

    //=========================================================
    // SECTION 15 — Hazard detection unit
    //=========================================================
    hazard_unit u_haz (
        .id_rs1_addr (id_rs1_addr),
        .id_rs2_addr (id_rs2_addr),
        .ex_rd_addr  (id_ex_rd_addr),
        .ex_mem_read (id_ex_mem_read),
        .stall_if    (stall_if),
        .stall_id    (stall_id),
        .flush_ex    (flush_ex_ldu)
    );

    //=========================================================
    // SECTION 16 — Debug outputs
    //=========================================================
    assign dbg_pc      = if_pc;
    assign dbg_instr   = imem_instr;
    assign dbg_wb_data = wb_data;
    assign dbg_wb_rd   = wb_rd;

endmodule
