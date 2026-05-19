module tb_control;
    reg  [6:0] opcode; reg [2:0] funct3; reg [6:0] funct7;
    wire [3:0] alu_op; wire reg_write, mem_read;

    control_unit dut(.opcode(opcode),.funct3(funct3),.funct7(funct7),
                     .alu_op(alu_op),.reg_write(reg_write),
                     .mem_read(mem_read),
                     // tie off unused outputs
                     .alu_src(),.instr_type(),.mem_write(),
                     .mem_width(),.wb_sel(),.branch(),.jump(),
                     .jump_jalr(),.illegal_instr());

    initial begin
        // Test ADD (R-type)
        opcode=7'b0110011; funct3=3'b000; funct7=7'b0000000;
        #10; $display("ADD: alu_op=%b reg_write=%b (expect 0000, 1)", alu_op, reg_write);

        // Test LW (load)
        opcode=7'b0000011; funct3=3'b010; funct7=7'b0;
        #10; $display("LW: alu_op=%b mem_read=%b (expect 0000, 1)", alu_op, mem_read);

        // Test ADDI
        opcode=7'b0010011; funct3=3'b000; funct7=7'b0;
        #10; $display("ADDI: alu_op=%b reg_write=%b (expect 0000, 1)", alu_op, reg_write);

        $finish;
    end
endmodule
