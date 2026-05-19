`timescale 1ns / 1ps
//------------------------------------------------------------
// alu.v
// 32-bit ALU for RV32I
// All operations combinational — no registers here
//
// alu_op encoding (matches control_unit.v):
//   4'b0000 = ADD        4'b0001 = SUB
//   4'b0010 = AND        4'b0011 = OR
//   4'b0100 = XOR        4'b0101 = SLL
//   4'b0110 = SRL        4'b0111 = SRA
//   4'b1000 = SLT        4'b1001 = SLTU
//   4'b1010 = LUI pass   (operand_b passed directly)
//   4'b1011 = AUIPC      (operand_a=PC, operand_b=upper imm)
//   4'b1111 = NOP/default → output 0
//------------------------------------------------------------
module alu (
    input  wire [31:0] operand_a,   // rs1 (or PC for AUIPC)
    input  wire [31:0] operand_b,   // rs2 or sign-extended immediate
    input  wire [3:0]  alu_op,

    output reg  [31:0] result,
    output wire        zero         // used for BEQ / BNE branch condition
);
    assign zero = (result == 32'h0);

    // Shift amount is always lower 5 bits of operand_b (RV32I spec)
    wire [4:0] shamt = operand_b[4:0];

    always @(*) begin
        case (alu_op)
            4'b0000: result = operand_a + operand_b;                    // ADD / ADDI
            4'b0001: result = operand_a - operand_b;                    // SUB
            4'b0010: result = operand_a & operand_b;                    // AND / ANDI
            4'b0011: result = operand_a | operand_b;                    // OR  / ORI
            4'b0100: result = operand_a ^ operand_b;                    // XOR / XORI
            4'b0101: result = operand_a << shamt;                       // SLL / SLLI
            4'b0110: result = operand_a >> shamt;                       // SRL / SRLI (logical)
            4'b0111: result = $signed(operand_a) >>> shamt;             // SRA / SRAI (arithmetic)
            4'b1000: result = ($signed(operand_a) < $signed(operand_b)) // SLT / SLTI
                              ? 32'h1 : 32'h0;
            4'b1001: result = (operand_a < operand_b)                   // SLTU / SLTIU
                              ? 32'h1 : 32'h0;
            4'b1010: result = operand_b;                                // LUI: pass imm straight
            4'b1011: result = operand_a + operand_b;                    // AUIPC: PC + upper imm
            default: result = 32'h0;
        endcase
    end

endmodule
