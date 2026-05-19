# RV32I Pipelined Core — Artix-7 FPGA Implementation

A fully synthesized, timing-closed 5-stage RV32I processor targeting the Xilinx Artix-7 (`xc7a35tcsg324-1`). Built in Vivado with BRAM-inferred register file and data memory, full forwarding and hazard detection, and post-implementation timing closure via RTL restructuring.

---

## What This Is

A ground-up Verilog implementation of the classic 5-stage RISC pipeline (IF → ID → EX → MEM → WB) for the RISC-V RV32I base integer ISA. The project goes past simulation correctness — it targets real FPGA fabric, enforces BRAM inference for the register file and data memory, and resolves timing violations identified from Vivado's post-implementation timing reports.

This is not a tutorial re-hash. Three specific problems separate it from generic student pipelines:

1. **BRAM inference** — replacing LUT-based register file arrays with properly structured synchronous read/write logic that Vivado maps to RAMB36E1 primitives. Confirmed in utilization report: `3× RAMB36E1`, `0 LUTs as Distributed RAM`.
2. **Forwarding and hazard correctness** — EX–EX and MEM–EX forwarding with correct priority (newer result wins), load-use stall detection with stall/flush signal OR logic, and store data bypass independent of the ALU src mux.
3. **Timing closure** — post-implementation WNS started at −1.4 ns on a 100 MHz constraint. Critical path traced: `rs1_addr FF → forwarding compare LUTs → mux → ALU carry chain → EX/MEM FF` (8 LUT levels). Fixed via pre-decoded registered forwarding selects, flat `case` mux synthesis, and branch comparator isolation from the ALU path.

---

## ISA Coverage

RV32I base integer subset — 37 instructions across 6 encoding formats:

| Format | Instructions |
|--------|-------------|
| R-type | ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU |
| I-type | ADDI, ANDI, ORI, XORI, SLLI, SRLI, SRAI, SLTI, SLTIU |
| I-type (load) | LW, LH, LB, LHU, LBU |
| S-type | SW, SH, SB |
| B-type | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| U-type | LUI, AUIPC |
| J-type | JAL, JALR |

B-type and J-type immediate encoding follows the RV32I spec's intentional bit-scrambling exactly — verified independently in `imm_gen.v`.

---

## File Structure

```
riscv_pipeline/
├── src/
│   ├── core/
│   │   ├── riscv_top.v          # top-level integration wrapper
│   │   ├── if_stage.v           # PC, instruction fetch, stall/flush
│   │   ├── id_stage.v           # decode, regfile read, imm gen, control
│   │   ├── ex_stage.v           # ALU, forwarding muxes, branch resolve
│   │   ├── mem_stage.v          # data memory interface, load extension
│   │   ├── wb_stage.v           # writeback mux (combinational only)
│   │   ├── control_unit.v       # opcode/funct3/funct7 → control signals
│   │   ├── alu.v                # 32-bit ALU, all RV32I operations
│   │   ├── imm_gen.v            # sign extension for all 6 formats
│   │   ├── forwarding_unit.v    # EX/MEM and MEM/WB forwarding selects
│   │   └── hazard_unit.v        # load-use stall detection
│   └── mem/
│       ├── regfile_bram.v       # 32×32 register file, BRAM inferred
│       ├── instr_mem.v          # synchronous ROM, BRAM inferred
│       └── data_mem.v           # byte-enable masked BRAM, sub-word R/W
├── tb/
│   ├── tb_riscv_top.v           # full pipeline testbench
│   ├── tb_alu.v
│   ├── tb_control.v
│   └── test_programs/
│       └── test1.mem            # hex program: forwarding + load-use cases
├── constraints/
│   └── artix7.xdc               # 100 MHz clock, IO delays
└── vivado/
    └── riscv_pipeline.xpr
```

---

## Architecture

### Pipeline Stages

```
       ┌────┐   ┌────┐   ┌────┐   ┌─────┐   ┌────┐
  clk  │ IF │ → │ ID │ → │ EX │ → │ MEM │ → │ WB │
       └────┘   └────┘   └────┘   └─────┘   └────┘
          ↑        ↑        │                   │
      stall_if  stall_id  branch_taken        wb_data
                           branch_target    → regfile write
```

**IF stage** — PC register with stall enable and branch/jump redirect mux. Drives synchronous instruction memory (1-cycle BRAM read latency accounted for in pipeline register placement).

**ID stage** — Instruction decode, immediate generation, register file read (two synchronous read ports → two RAMB36E1 primitives), control signal generation. Hazard unit reads combinational rs1/rs2 addresses from here. Pre-decoded forwarding selects registered into ID/EX to break the forwarding-compare → mux → ALU critical path.

**EX stage** — Forwarding muxes (3:1 per operand), 32-bit ALU, branch comparator (isolated from ALU src mux path), branch/jump target adder. Branch resolution happens here — 2-instruction flush penalty on taken branches (static not-taken prediction).

**MEM stage** — Byte-enable masked BRAM writes for SB/SH/SW. Synchronous read with sign/zero extension applied combinationally after BRAM registered output (LB/LH/LBU/LHU/LW). No extra pipeline register added here — BRAM read latency aligns naturally with MEM/WB register.

**WB stage** — Combinational 3:1 mux selecting between ALU result, load data, and PC+4 (link address for JAL/JALR). Feeds directly back to register file write port in ID.

### Forwarding

```
         EX/MEM.alu_result ──────────────────────┐
                                                  ↓
  ID/EX.rs1_addr ──→ [ pre-decoded select ] ──→ [ 3:1 mux ] ──→ ALU operand A
                                                  ↑
         MEM/WB.wb_data   ──────────────────────┘
```

- **EX–EX forward** (`fwd = 2'b01`): instruction in EX reads result of instruction now in MEM.
- **MEM–EX forward** (`fwd = 2'b10`): instruction in EX reads result of instruction now in WB.
- EX/MEM case checked first — newer result always wins over older.
- x0 guarded in all forwarding comparisons (never forwarded).
- Store data forwarding (`fwd_rs2_data`) captured before ALU src mux — prevents store instructions writing garbage when their source register was produced recently.

### Hazard Detection

Load-use hazard: detected when `id_ex_mem_read = 1` and `id_ex_rd` matches `id_rs1` or `id_rs2`. Response: assert `stall_if`, `stall_id`, `flush_ex` for one cycle. After the stall, MEM–EX forwarding resolves the dependency.

Branch/jump flush: `branch_taken` from EX stage ORed with `stall_if` to flush IF/ID and ID/EX on the same cycle.

---

## BRAM Inference

Register file and data memory are structured to satisfy Vivado's BRAM inference requirements:

- All reads synchronous (`always @(posedge clk)`)
- `(* ram_style = "block" *)` attribute on all arrays
- No reset inside read `always` blocks
- Separate `always` blocks for read and write
- No conditional gating on the read assignment itself

Result confirmed in `report_utilization`:

```
Block RAM Tile              : 3 / 50
  RAMB36E1                 : 3
LUTs as Distributed RAM    : 0
```

---

## Timing Closure

**Target:** 100 MHz (`create_clock -period 10.000`) on Artix-7 speed grade -1.

**Initial WNS:** −1.423 ns. Critical path: `id_ex_rs1_addr_reg → forwarding compare LUTs → mux LUTs → ALU carry chain → ex_mem_alu_result_r_reg` — 8 LUT levels, 11.4 ns total (logic 5.2 ns + route 6.2 ns).

**Fixes applied:**

| Fix | Technique | LUT levels saved | WNS improvement |
|-----|-----------|-----------------|-----------------|
| 1 | Pre-decode forwarding selects in ID stage, register into ID/EX | −2 | ~1.0 ns |
| 2 | Replace priority if-else mux with flat `case` statement | −1 | ~0.5 ns |
| 3 | Isolate branch comparator from ALU operand path | parallel path | branch path no longer stacked |

**Final WNS:** +0.124 ns (timing closed at 100 MHz).

---

## Simulation Verification

Test program (`test1.mem`) covers:

- EX–EX forwarding: `ADDI x1` followed immediately by `ADD x2, x1, ...` — `fwd_a = 2'b01` asserts.
- MEM–EX forwarding: result used two instructions after write — `fwd_a = 2'b10` asserts.
- Load-use stall: `LW x3` followed by `ADD x4, x3, ...` — `stall_if` and `flush_ex` assert for exactly one cycle.
- Branch flush: `JAL` — `branch_taken` asserts, two NOP bubbles visible in pipeline registers.
- Sub-word load extension: `LB` sign-extends `0xFF` to `0xFFFFFFFF`, `LBU` zero-extends to `0x000000FF`.

---

## Implementation Checklist

```
☑ report_timing_summary: WNS ≥ 0.0 ns
☑ report_utilization: 3× RAMB36E1, LUTs as Distributed RAM = 0
☑ report_utilization: ~900–1200 total LUTs
☑ report_clock_interaction: no CDC violations (single clock domain)
☑ report_drc: no violations
☑ Behavioral simulation: all forwarding cases correct
☑ Behavioral simulation: load-use stall = exactly 1 cycle
☑ Behavioral simulation: branch flush squashes exactly 2 instructions
```

---

## Tools & Target

| Item | Value |
|------|-------|
| HDL | Verilog (IEEE 1364-2001) |
| Synthesis & Implementation | Vivado 2023.x |
| Target device | `xc7a35tcsg324-1` (Artix-7) |
| Compatible boards | Basys3, Arty A7-35T |
| Clock constraint | 100 MHz |
| ISA | RISC-V RV32I |
