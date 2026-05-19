`timescale 1ns / 1ps
//------------------------------------------------------------
// control_unit.v
// Decodes opcode + funct3 + funct7 into pipeline control signals
//
// ALU operation encoding (alu_op):
//   4'b0000 = ADD       4'b0001 = SUB
//   4'b0010 = AND       4'b0011 = OR
//   4'b0100 = XOR       4'b0101 = SLL
//   4'b0110 = SRL       4'b0111 = SRA
//   4'b1000 = SLT       4'b1001 = SLTU
//   4'b1010 = LUI pass  4'b1011 = AUIPC add
//   4'b1111 = NOP/default
//------------------------------------------------------------

// Opcode definitions — avoids magic numbers in code
`define OP_R      7'b0110011    // R-type
`define OP_I_ALU  7'b0010011    // I-type ALU
`define OP_LOAD   7'b0000011    // Loads
`define OP_STORE  7'b0100011    // Stores
`define OP_BRANCH 7'b1100011    // Branches
`define OP_JAL    7'b1101111    // JAL
`define OP_JALR   7'b1100111    // JALR
`define OP_LUI    7'b0110111    // LUI
`define OP_AUIPC  7'b0010111    // AUIPC

module control_unit (
    input  wire [6:0]  opcode,
    input  wire [2:0]  funct3,
    input  wire [6:0]  funct7,

    // EX stage controls
    output reg  [3:0]  alu_op,       // which ALU operation
    output reg         alu_src,      // 0=register rs2, 1=immediate
    output reg  [2:0]  instr_type,   // for immediate generator

    // MEM stage controls
    output reg         mem_read,     // 1 = load instruction
    output reg         mem_write,    // 1 = store instruction
    output reg  [2:0]  mem_width,    // funct3 passed through for byte/half/word

    // WB stage controls
    output reg         reg_write,    // 1 = write result to register file
    output reg  [1:0]  wb_sel,       // 00=ALU result, 01=mem data, 10=PC+4 (link)

    // Branch/jump controls (resolved in EX)
    output reg         branch,       // 1 = conditional branch
    output reg         jump,         // 1 = unconditional jump (JAL/JALR)
    output reg         jump_jalr,    // 1 = JALR (target = rs1+imm, not PC+imm)

    // Illegal instruction flag
    output reg         illegal_instr
);

    always @(*) begin
        // Safe defaults — prevents latches
        alu_op        = 4'b1111;
        alu_src       = 1'b0;
        instr_type    = 3'b101;     // R-type default (no imm)
        mem_read      = 1'b0;
        mem_write     = 1'b0;
        mem_width     = funct3;
        reg_write     = 1'b0;
        wb_sel        = 2'b00;
        branch        = 1'b0;
        jump          = 1'b0;
        jump_jalr     = 1'b0;
        illegal_instr = 1'b0;

        case (opcode)

            `OP_R: begin
                reg_write  = 1'b1;
                alu_src    = 1'b0;
                instr_type = 3'b101;
                case ({funct7, funct3})
                    10'b0000000_000: alu_op = 4'b0000; // ADD
                    10'b0100000_000: alu_op = 4'b0001; // SUB
                    10'b0000000_111: alu_op = 4'b0010; // AND
                    10'b0000000_110: alu_op = 4'b0011; // OR
                    10'b0000000_100: alu_op = 4'b0100; // XOR
                    10'b0000000_001: alu_op = 4'b0101; // SLL
                    10'b0000000_101: alu_op = 4'b0110; // SRL
                    10'b0100000_101: alu_op = 4'b0111; // SRA
                    10'b0000000_010: alu_op = 4'b1000; // SLT
                    10'b0000000_011: alu_op = 4'b1001; // SLTU
                    default:         illegal_instr = 1'b1;
                endcase
            end

            `OP_I_ALU: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                instr_type = 3'b000;
                case (funct3)
                    3'b000: alu_op = 4'b0000; // ADDI
                    3'b111: alu_op = 4'b0010; // ANDI
                    3'b110: alu_op = 4'b0011; // ORI
                    3'b100: alu_op = 4'b0100; // XORI
                    3'b001: alu_op = 4'b0101; // SLLI (funct7 check omitted for brevity)
                    3'b101: alu_op = (funct7[5]) ? 4'b0111 : 4'b0110; // SRAI : SRLI
                    3'b010: alu_op = 4'b1000; // SLTI
                    3'b011: alu_op = 4'b1001; // SLTIU
                    default: illegal_instr = 1'b1;
                endcase
            end

            `OP_LOAD: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                alu_op     = 4'b0000; // ADD — compute address
                instr_type = 3'b000;
                mem_read   = 1'b1;
                wb_sel     = 2'b01;   // WB from memory
            end

            `OP_STORE: begin
                alu_src    = 1'b1;
                alu_op     = 4'b0000; // ADD — compute address
                instr_type = 3'b001;
                mem_write  = 1'b1;
            end

            `OP_BRANCH: begin
                alu_src    = 1'b0;
                instr_type = 3'b010;
                branch     = 1'b1;
                // funct3 encodes BEQ/BNE/BLT/BGE/BLTU/BGEU
                // pass funct3 through — branch condition resolved in EX
            end

            `OP_JAL: begin
                reg_write  = 1'b1;
                alu_op     = 4'b0000;
                instr_type = 3'b100;  // J-type immediate
                jump       = 1'b1;
                wb_sel     = 2'b10;   // WB = PC+4 (link address)
            end

            `OP_JALR: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                alu_op     = 4'b0000;
                instr_type = 3'b000;  // I-type immediate
                jump       = 1'b1;
                jump_jalr  = 1'b1;
                wb_sel     = 2'b10;
            end

            `OP_LUI: begin
                reg_write  = 1'b1;
                alu_op     = 4'b1010; // LUI: pass upper imm
                instr_type = 3'b011;
                alu_src    = 1'b1;
            end

            `OP_AUIPC: begin
                reg_write  = 1'b1;
                alu_op     = 4'b1011; // AUIPC: PC + upper imm
                instr_type = 3'b011;
                alu_src    = 1'b1;
            end

            default: begin
                illegal_instr = 1'b1;
            end

        endcase
    end

endmodule
