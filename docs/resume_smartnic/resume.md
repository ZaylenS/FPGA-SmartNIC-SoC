# Zilin Shao

Los Angeles, CA | Open to Relocation | zilinshaodev@gmail.com

*Source: `C:\Dev\Resume\Resume_first_version_2026_1.pdf` — extracted 2026-05-04*

## Education

**M.S. in Computer Engineering**, University of Southern California — Expected May 2026
Coursework: Hardware Foundations of Machine Learning, VLSI Design, Computer Architecture, Diagnosis and Design of Reliable Digital Systems

**B.S. in Computer Science & Mathematics**, The Ohio State University — Aug 2023

## Projects

### FPGA SoC with ARM CPU, Custom SIMD GPU, and On-Chip IDS Inference — Spring 2026
*Verilog, Python, C, Xilinx ISE, Icarus Verilog, ARM GCC, NetFPGA Virtex-II Pro*

- Architected and implemented a heterogeneous SoC on Xilinx Virtex-II Pro integrating a quad-thread pipelined ARM CPU, custom 4-lane SIMD GPU, DMA engine, and mode-switchable packet FIFO; delivered 7,800+ lines of synthesizable Verilog, hardware-verified on physical NetFPGA boards.
- Designed a custom 15-opcode GPU ISA with a 3-stage pipelined BFloat16 FMA unit and built a CUDA/PTX-to-hardware compilation toolchain; improved critical-path timing from 21.4 ns to 14.1 ns through pipeline restructuring, reaching 96% slice utilization.
- Deployed an MLP-based network intrusion detection system on-chip (Ethernet → FIFO → DMA → GPU inference), executing a 211-instruction BFloat16 kernel in ~19.2 µs at 125 MHz; validated attack/normal classification on live packet tests.

### Digital Circuit Fault Simulator and ATPG Engine — Fall 2025
*C++11, Python, CMake, Git, Linux*

- Built a 6,500+ LOC C++ EDA tool for ISCAS-85 combinational circuits, implementing netlist parsing, levelization, logic simulation, and single stuck-at fault analysis on benchmarks up to c6288 (~2,400 gates / ~7,700 faults).
- Implemented D-Algorithm and PODEM test generation with SCOAP-guided heuristics, plus deductive and bit-parallel fault simulation achieving up to 63× parallelism per pass on 64-bit hosts.
- Designed a hybrid RTPG+ATPG engine with configurable fault ordering, D-frontier selection, and justification strategies; integrated fault dropping with parallel fault simulation to reduce runtime on hard-to-detect faults.

### CUDA GPU Programming — Matrix Multiplication and Image Convolution — Spring 2026
*CUDA, C, Python, Google Cloud Platform (Tesla T4 / V100)*

- Implemented and benchmarked CUDA matrix multiplication kernels (naive, shared-memory tiled, cuBLAS) on cloud GPU instances; achieved over 10,000× speedup vs. single-threaded CPU at N=4096 through shared memory tiling and coalesced memory access.
- Developed GPU-accelerated Sobel edge detection using shared memory tiling and constant memory; built Python-callable CUDA shared libraries via ctypes for integrated CPU/GPU performance benchmarking.

## Technical Skills

| Category | Skills |
|---|---|
| **Languages** | Verilog, C++, C, Python, CUDA |
| **Hardware/Arch.** | RTL Design, Pipelined Microarchitecture, FSM, Hazard Handling, DMA, FPGA Synthesis, Timing Analysis, Verification, DFT, ATPG, Fault Simulation |
| **Tools/Platforms** | Xilinx ISE, Vivado, Icarus Verilog, CMake, Git, Linux, ARM GCC, NetFPGA, Xilinx Virtex-II Pro, Google Cloud GPU |
| **ML/Acceleration** | BFloat16 Datapath Design, SIMD Accelerator Design, On-Chip ML Inference, GPU Programming |
| **Networking** | TCP/IP, UDP, RDMA (RoCE / iWARP) |
