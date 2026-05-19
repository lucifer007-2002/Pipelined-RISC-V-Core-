`timescale 1ns / 1ps
//------------------------------------------------------------
// id_stage.v
// Instruction Decode stage
// Instantiates control_unit, imm_gen, regfile_bram
// Drives the ID/EX pipeline register
//------------------------------------------------------------
module id_stage (
    input  wire        clk,
    input  wire        rst,

    // From IF/ID register
    input  wire [31:0] if_id_pc,
    input  wire [31:0] if_id_pc_plus4,
    input  wire [31:0] if_id_instr,
    input  wire        if_id_valid,

    // Hazard unit controls
    input  wire        stall,        // freeze ID/EX register
    input  wire        flush,        // inject NOP into ID/EX register

    // WB writeback (forwarded into register file write port)
    input  wire [4:0]  wb_rd,
    input  wire [31:0] wb_data,
    input  wire        wb_reg_write,

    // ── ID/EX pipeline register outputs ──────────────────────
    // Data signals
    output reg  [31:0] id_ex_pc,
    output reg  [31:0] id_ex_pc_plus4,
    output reg  [31:0] id_ex_rs1_data,
    output reg  [31:0] id_ex_rs2_data,
    output reg  [31:0] id_ex_imm,
    output reg  [4:0]  id_ex_rs1_addr,   // needed by forwarding unit
    output reg  [4:0]  id_ex_rs2_addr,
    output reg  [4:0]  id_ex_rd_addr,
    output reg  [2:0]  id_ex_funct3,

    // Control signals passed downstream
    output reg  [3:0]  id_ex_alu_op,
    output reg         id_ex_alu_src,
    output reg         id_ex_mem_read,
    output reg         id_ex_mem_write,
    output reg  [2:0]  id_ex_mem_width,
    output reg         id_ex_reg_write,
    output reg  [1:0]  id_ex_wb_sel,
    output reg         id_ex_branch,
    output reg         id_ex_jump,
    output reg         id_ex_jump_jalr,

    // For hazard detection
    output wire [4:0]  id_rs1_addr,    // combinational — hazard unit reads these
    output wire [4:0]  id_rs2_addr
);

    // ── Instruction field extraction (combinational) ──────────
    wire [6:0]  opcode  = if_id_instr[6:0];
    wire [4:0]  rd      = if_id_instr[11:7];
    wire [2:0]  funct3  = if_id_instr[14:12];
    wire [4:0]  rs1     = if_id_instr[19:15];
    wire [4:0]  rs2     = if_id_instr[24:20];
    wire [6:0]  funct7  = if_id_instr[31:25];

    assign id_rs1_addr = rs1;
    assign id_rs2_addr = rs2;

    // ── Control unit ──────────────────────────────────────────
    wire [3:0]  alu_op;
    wire        alu_src;
    wire [2:0]  instr_type;
    wire        mem_read, mem_write;
    wire [2:0]  mem_width;
    wire        reg_write;
    wire [1:0]  wb_sel;
    wire        branch, jump, jump_jalr;
    wire        illegal_instr;

    control_unit u_ctrl (
        .opcode       (opcode),
        .funct3       (funct3),
        .funct7       (funct7),
        .alu_op       (alu_op),
        .alu_src      (alu_src),
        .instr_type   (instr_type),
        .mem_read     (mem_read),
        .mem_write    (mem_write),
        .mem_width    (mem_width),
        .reg_write    (reg_write),
        .wb_sel       (wb_sel),
        .branch       (branch),
        .jump         (jump),
        .jump_jalr    (jump_jalr),
        .illegal_instr(illegal_instr)
    );

    // ── Immediate generator ───────────────────────────────────
    wire [31:0] imm;

    imm_gen u_immgen (
        .instr      (if_id_instr),
        .instr_type (instr_type),
        .imm_out    (imm)
    );

    // ── Register file ─────────────────────────────────────────
    wire [31:0] rs1_data, rs2_data;

    regfile_bram u_regfile (
        .clk  (clk),
        .ra1  (rs1),
        .rd1  (rs1_data),
        .ra2  (rs2),
        .rd2  (rs2_data),
        .wa   (wb_rd),
        .wd   (wb_data),
        .we   (wb_reg_write)
    );

    // ── ID/EX pipeline register ───────────────────────────────
    // On flush or invalid instruction: inject a NOP bubble
    // (all control signals = 0, no side-effects downstream)
    wire bubble = rst || flush || !if_id_valid;

    always @(posedge clk) begin
        if (bubble) begin
            id_ex_pc          <= 32'h0;
            id_ex_pc_plus4    <= 32'h0;
            id_ex_rs1_data    <= 32'h0;
            id_ex_rs2_data    <= 32'h0;
            id_ex_imm         <= 32'h0;
            id_ex_rs1_addr    <= 5'h0;
            id_ex_rs2_addr    <= 5'h0;
            id_ex_rd_addr     <= 5'h0;
            id_ex_funct3      <= 3'h0;
            // All control signals cleared = NOP
            id_ex_alu_op      <= 4'b1111;
            id_ex_alu_src     <= 1'b0;
            id_ex_mem_read    <= 1'b0;
            id_ex_mem_write   <= 1'b0;
            id_ex_mem_width   <= 3'h0;
            id_ex_reg_write   <= 1'b0;
            id_ex_wb_sel      <= 2'b00;
            id_ex_branch      <= 1'b0;
            id_ex_jump        <= 1'b0;
            id_ex_jump_jalr   <= 1'b0;
        end else if (!stall) begin
            id_ex_pc          <= if_id_pc;
            id_ex_pc_plus4    <= if_id_pc_plus4;
            id_ex_rs1_data    <= rs1_data;
            id_ex_rs2_data    <= rs2_data;
            id_ex_imm         <= imm;
            id_ex_rs1_addr    <= rs1;
            id_ex_rs2_addr    <= rs2;
            id_ex_rd_addr     <= rd;
            id_ex_funct3      <= funct3;
            id_ex_alu_op      <= alu_op;
            id_ex_alu_src     <= alu_src;
            id_ex_mem_read    <= mem_read;
            id_ex_mem_write   <= mem_write;
            id_ex_mem_width   <= mem_width;
            id_ex_reg_write   <= reg_write;
            id_ex_wb_sel      <= wb_sel;
            id_ex_branch      <= branch;
            id_ex_jump        <= jump;
            id_ex_jump_jalr   <= jump_jalr;
        end
        // stall: ID/EX register holds — upstream replays
    end

endmodule
