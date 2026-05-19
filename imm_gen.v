`timescale 1ns / 1ps
//------------------------------------------------------------
// imm_gen.v
// Immediate sign-extension for all RV32I instruction formats
// instr_type encoding (from control_unit):
//   3'b000 = I-type
//   3'b001 = S-type
//   3'b010 = B-type
//   3'b011 = U-type
//   3'b100 = J-type
//   3'b101 = R-type (no immediate — output 0)
//------------------------------------------------------------
module imm_gen (
    input  wire [31:0] instr,
    input  wire [2:0]  instr_type,
    output reg  [31:0] imm_out
);

    always @(*) begin
        case (instr_type)

            3'b000: // I-type: loads, ALU-immediate, JALR
                // imm[11:0] = instr[31:20], sign-extended
                imm_out = {{20{instr[31]}}, instr[31:20]};

            3'b001: // S-type: stores
                // imm[11:5] = instr[31:25], imm[4:0] = instr[11:7]
                imm_out = {{20{instr[31]}}, instr[31:25], instr[11:7]};

            3'b010: // B-type: branches
                // imm[12]   = instr[31]
                // imm[11]   = instr[7]       ← this bit moves — common bug
                // imm[10:5] = instr[30:25]
                // imm[4:1]  = instr[11:8]
                // imm[0]    = 0              ← always 0, branches are 2-byte aligned
                imm_out = {{19{instr[31]}},
                            instr[31],
                            instr[7],
                            instr[30:25],
                            instr[11:8],
                            1'b0};

            3'b011: // U-type: LUI, AUIPC
                // imm[31:12] = instr[31:12], imm[11:0] = 0
                imm_out = {instr[31:12], 12'b0};

            3'b100: // J-type: JAL
                // imm[20]    = instr[31]
                // imm[19:12] = instr[19:12]  ← jumps across the bit ordering
                // imm[11]    = instr[20]
                // imm[10:1]  = instr[30:21]
                // imm[0]     = 0
                imm_out = {{11{instr[31]}},
                            instr[31],
                            instr[19:12],
                            instr[20],
                            instr[30:21],
                            1'b0};

            default: // R-type or unknown: no immediate
                imm_out = 32'h0;

        endcase
    end

endmodule
