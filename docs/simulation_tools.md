# Simulation Tooling Notes

Updated 2026-06-25 after checking the local Windows environment and current upstream tool documentation.

## Local Availability

- Icarus Verilog is installed at `C:\iverilog\bin`.
- `C:\iverilog\bin` has been added to the persisted System `Path`. Existing long-lived shells may still need a restart or manual PATH refresh before `iverilog` and `vvp` resolve by name.
- Local version checked: Icarus Verilog 12.0 development snapshot.
- Vivado 2024.1 is installed at `C:\Xilinx\Vivado\2024.1\bin`.
- `C:\Xilinx\Vivado\2024.1\bin` has been added to the persisted System `Path`. Existing long-lived shells may still need a restart or manual PATH refresh before `vivado`, `xvlog`, `xelab`, and `xsim` resolve by name.
- Vivado CLI launchers verified:
  - `C:\Xilinx\Vivado\2024.1\bin\vivado.bat -version` prints `vivado v2024.1 (64-bit)`, SW Build 5076996.
  - `C:\Xilinx\Vivado\2024.1\bin\xvlog.bat --version` prints `Vivado Simulator v2024.1`.
  - `C:\Xilinx\Vivado\2024.1\bin\xelab.bat --version` prints `Vivado Simulator v2024.1`.
  - `C:\Xilinx\Vivado\2024.1\bin\xsim.bat --version` prints `Vivado Simulator v2024.1`.
- Verilator, Yosys, and WSL are not visible in this Windows shell.

## Verified Smoke Test

This repo's BCAST IDS testbench compiles and runs with the local Icarus install:

```powershell
C:\iverilog\bin\iverilog.exe -g2001 -I include -o $env:TEMP\tb_ids_bcast_codex.vvp src/gpu/gpu_top.v src/gpu/core_top.v src/gpu/program_counter.v src/gpu/instruction_memory.v src/gpu/data_memory.v src/gpu/fetch_stage.v src/gpu/decode_stage.v src/gpu/instruction_decoder.v src/gpu/register_file.v src/gpu/pipeline_reg_idex.v src/gpu/pipeline_reg_ex.v src/gpu/pipeline_reg_exwb.v src/gpu/execute_stage.v src/gpu/simd_alu.v src/gpu/int16_alu.v src/gpu/bf16_alu.v src/gpu/bf16_fma_unit.v src/gpu/hazard_unit.v src/gpu/writeback_stage.v tb/tb_ids_bcast.v
C:\iverilog\bin\vvp.exe $env:TEMP\tb_ids_bcast_codex.vvp
```

Observed result: 26 PASS, 0 FAIL; GPU halted after 732 cycles. The `$readmemh` "not enough words" warnings are expected because the memory arrays are larger than the hex files.

Vivado 2024.1 XSim front-end access was also verified from a temp work directory:

- `xvlog.bat` successfully analyzed the GPU source set plus `tb/tb_ids_bcast.v`.
- `xelab.bat tb_ids_bcast -s tb_ids_bcast_codex` successfully elaborated the testbench and built a simulation snapshot.
- Full `xsim -runall` was not run in that temp directory because this testbench's `$readmemh` paths expect `programs/gpu/...` relative to the simulation working directory.

The smaller `tb/tb_bcast.v` unit test compiles, but runtime currently fails because `programs/gpu/bcast_test.hex` and `programs/gpu/data_bcast_test.hex` are not present in this checkpoint. That is an asset issue, not an Icarus issue.

No heredoc or column-sensitive delimiter lines are used in the commands above; accidental leading spaces before these PowerShell commands do not change behavior.

## Recommended Use

- Use Icarus Verilog first for existing Verilog-2001 RTL/testbenches. It is already installed, fast enough, event-driven, and matches the repo's historical CLI flow.
- Use Verilator when a subsystem needs faster repeated simulation, stronger linting, or a C++/Python-driven harness. Expect adaptation work for legacy Verilog testbenches, especially where timing controls, 4-state behavior, or pure testbench constructs matter.
- Use Vivado XSim in the Ubuntu/Vivado VM for modern Xilinx-facing signoff, Xilinx simulation libraries, mixed-language/IP cases, or post-synthesis/post-implementation simulation.
- Use the local Windows Vivado 2024.1 install when a Xilinx simulator check is useful from this host. Use the Ubuntu/Vivado VM if the flow depends on Linux paths, project scripts, or parity with other SmartNIC work.
- Use Yosys for synthesis/formal/elaboration checks, not as the main drop-in replacement for existing behavioral testbenches.

## Upstream References

- Icarus Verilog docs: https://steveicarus.github.io/iverilog/
- Icarus Verilog releases: https://github.com/steveicarus/iverilog/releases
- Verilator docs: https://verilator.org/guide/latest/
- AMD Vivado Logic Simulation UG900 2024.1: https://docs.amd.com/r/2024.1-English/ug900-vivado-logic-simulation/
- Yosys docs: https://yosyshq.readthedocs.io/projects/yosys/en/latest/
