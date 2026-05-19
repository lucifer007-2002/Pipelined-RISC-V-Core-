`timescale 1ns / 1ps
//------------------------------------------------------------
// ex_stage.v
// Execute stage — the combinationally deepest stage
//
// Critical paths in this module (what Vivado will flag):
//   1. fwd_a/fwd_b → forwarding mux → ALU operand_a/b → ALU result
//      → EX/MEM register. This is your longest combo path.
//   2. Branch comparator path: forwarded rs1/rs2 → subtract/compare
//      → branch_taken → back to IF PC mux (multi-stage feedback)
//
// Both will be addressed in Part 6 timing analysis.
//------------------------------------------------------------
module ex_stage (
    input  wire        clk,
    input  wire        rst,

    // ── From ID/EX pipeline register ─────────────────────────
    input  wire [31:0] id_ex_pc,
    input  wire [31:0] id_ex_pc_plus4,
    input  wire [31:0] id_ex_rs1_data,
    input  wire [31:0] id_ex_rs2_data,
    input  wire [31:0] id_ex_imm,
    input  wire [4:0]  id_ex_rs1_addr,
    input  wire [4:0]  id_ex_rs2_addr,
    input  wire [4:0]  id_ex_rd_addr,
    input  wire [2:0]  id_ex_funct3,

    // Control signals
    input  wire [3:0]  id_ex_alu_op,
    input  wire        id_ex_alu_src,
    input  wire        id_ex_mem_read,
    input  wire        id_ex_mem_write,
    input  wire [2:0]  id_ex_mem_width,
    input  wire        id_ex_reg_write,
    input  wire [1:0]  id_ex_wb_sel,
    input  wire        id_ex_branch,
    input  wire        id_ex_jump,
    input  wire        id_ex_jump_jalr,

    // ── Forwarding inputs ─────────────────────────────────────
    input  wire [1:0]  fwd_a,             // from forwarding_unit
    input  wire [1:0]  fwd_b,
    input  wire [31:0] ex_mem_alu_result, // EX/MEM forwarding data
    input  wire [31:0] mem_wb_wb_data,    // MEM/WB forwarding data

    // ── Hazard flush ──────────────────────────────────────────
    input  wire        flush,             // from hazard_unit (load-use stall)

    // ── Branch/jump resolution → IF stage ────────────────────
    output reg         branch_taken,      // 1 = redirect PC
    output reg  [31:0] branch_target,     // target address

    // ── EX/MEM pipeline register outputs ─────────────────────
    output reg  [31:0] ex_mem_alu_result_r,
    output reg  [31:0] ex_mem_rs2_data,   // forwarded rs2 (for stores)
    output reg  [4:0]  ex_mem_rd_addr,
    output reg  [31:0] ex_mem_pc_plus4,
    output reg         ex_mem_mem_read,
    output reg         ex_mem_mem_write,
    output reg  [2:0]  ex_mem_mem_width,
    output reg         ex_mem_reg_write,
    output reg  [1:0]  ex_mem_wb_sel
);

    // ── Forwarding muxes ──────────────────────────────────────
    // Select the correct value for ALU operand A (rs1 source)
    reg [31:0] alu_in_a;
    always @(*) begin
        case (fwd_a)
            2'b00:   alu_in_a = id_ex_rs1_data;      // no forward
            2'b01:   alu_in_a = ex_mem_alu_result;   // EX-EX forward
            2'b10:   alu_in_a = mem_wb_wb_data;      // MEM-EX forward
            default: alu_in_a = id_ex_rs1_data;
        endcase
    end

    // Forwarded rs2 (used before ALU src mux — stores need the raw rs2)
    reg [31:0] fwd_rs2_data;
    always @(*) begin
        case (fwd_b)
            2'b00:   fwd_rs2_data = id_ex_rs2_data;
            2'b01:   fwd_rs2_data = ex_mem_alu_result;
            2'b10:   fwd_rs2_data = mem_wb_wb_data;
            default: fwd_rs2_data = id_ex_rs2_data;
        endcase
    end

    // ALU src mux: rs2 register or immediate
    // NOTE: stores use forwarded rs2 as the DATA to write (not the address).
    //       The address is rs1+imm — that goes into the ALU.
    //       The forwarded rs2 bypasses the ALU src mux and goes directly
    //       to EX/MEM as ex_mem_rs2_data.
    wire [31:0] alu_in_b = id_ex_alu_src ? id_ex_imm : fwd_rs2_data;

    // ── ALU ───────────────────────────────────────────────────
    // AUIPC uses PC as operand_a instead of rs1
    wire [31:0] alu_operand_a = (id_ex_alu_op == 4'b1011) ? id_ex_pc : alu_in_a;

    wire [31:0] alu_result;
    wire        alu_zero;

    alu u_alu (
        .operand_a (alu_operand_a),
        .operand_b (alu_in_b),
        .alu_op    (id_ex_alu_op),
        .result    (alu_result),
        .zero      (alu_zero)
    );

    // ── Branch comparator ─────────────────────────────────────
    // RV32I branches compare rs1 and rs2 directly — not via ALU result.
    // We reuse the forwarded operands but run a separate comparison.
    // funct3 encodes the condition.
    wire        branch_cond;
    wire [32:0] signed_diff = {1'b0, alu_in_a} - {1'b0, fwd_rs2_data};

    assign branch_cond =
        (id_ex_funct3 == 3'b000) ?  (alu_in_a == fwd_rs2_data)          : // BEQ
        (id_ex_funct3 == 3'b001) ?  (alu_in_a != fwd_rs2_data)          : // BNE
        (id_ex_funct3 == 3'b100) ?  ($signed(alu_in_a) <  $signed(fwd_rs2_data)) : // BLT
        (id_ex_funct3 == 3'b101) ?  ($signed(alu_in_a) >= $signed(fwd_rs2_data)) : // BGE
        (id_ex_funct3 == 3'b110) ?  (alu_in_a  <  fwd_rs2_data)         : // BLTU
        (id_ex_funct3 == 3'b111) ?  (alu_in_a  >= fwd_rs2_data)         : // BGEU
        1'b0;

    // ── Branch/jump target computation ───────────────────────
    // Branch: PC + sign-extended B-type immediate
    // JAL:    PC + sign-extended J-type immediate
    // JALR:   (rs1 + I-type immediate) AND ~1  (clear bit 0 per spec)
    wire [31:0] branch_or_jal_target = id_ex_pc + id_ex_imm;
    wire [31:0] jalr_target          = (alu_in_a + id_ex_imm) & ~32'h1;

    // ── branch_taken and branch_target (combinational) ────────
    always @(*) begin
        branch_taken  = 1'b0;
        branch_target = 32'h0;

        if (id_ex_jump) begin
            // Unconditional: JAL or JALR always taken
            branch_taken  = 1'b1;
            branch_target = id_ex_jump_jalr ? jalr_target : branch_or_jal_target;
        end else if (id_ex_branch && branch_cond) begin
            // Conditional branch, condition true
            branch_taken  = 1'b1;
            branch_target = branch_or_jal_target;
        end
    end

    // ── EX/MEM pipeline register ──────────────────────────────
    wire bubble = rst || flush;

    always @(posedge clk) begin
        if (bubble) begin
            ex_mem_alu_result_r <= 32'h0;
            ex_mem_rs2_data     <= 32'h0;
            ex_mem_rd_addr      <= 5'h0;
            ex_mem_pc_plus4     <= 32'h0;
            ex_mem_mem_read     <= 1'b0;
            ex_mem_mem_write    <= 1'b0;
            ex_mem_mem_width    <= 3'h0;
            ex_mem_reg_write    <= 1'b0;
            ex_mem_wb_sel       <= 2'b00;
        end else begin
            ex_mem_alu_result_r <= alu_result;
            ex_mem_rs2_data     <= fwd_rs2_data;  // forwarded rs2 for stores
            ex_mem_rd_addr      <= id_ex_rd_addr;
            ex_mem_pc_plus4     <= id_ex_pc_plus4;
            ex_mem_mem_read     <= id_ex_mem_read;
            ex_mem_mem_write    <= id_ex_mem_write;
            ex_mem_mem_width    <= id_ex_mem_width;
            ex_mem_reg_write    <= id_ex_reg_write;
            ex_mem_wb_sel       <= id_ex_wb_sel;
        end
    end

endmodule
