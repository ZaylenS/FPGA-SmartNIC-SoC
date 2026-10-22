# Lab 10 Demo Video Script

**Duration: ~5 minutes. Audio recorded separately -- read the transcript below as a single voiceover.**

---

## Pre-Recording Setup

1. FPGA already programmed: `nf_download nf2_top_par.bit`
2. Files deployed to nf5 (~/zil_team12/refinements_lab10/) and node0 (~/zil_team12/)
3. Two terminals open: left = nf5 (FPGA), right = node0

---

## Video Actions (in order)

### Part 1: Load Model onto FPGA (~30 sec)

On nf5:
```bash
python lab10reg.py ids_load
```

### Part 2-6: Alternating Normal and Attack Classification (~3 min)

Repeat 5 rounds. Each round: start receiver on nf5, then send from node0.

**Round 1 -- Attack (default sample):**
```bash
# nf5:
python lab10reg.py ids_from_packet
# node0:
python send_ids.py
```

**Round 2 -- Normal (high same-srv-rate, low error):**
```bash
# nf5:
python lab10reg.py ids_from_packet
# node0:
python send_ids.py 0.0 0.0 1.0 0.0 0.61 0.0 0.337 0.04 0.0 0.61 0.002
```

**Round 3 -- Attack (high connection count, low same-srv-rate):**
```bash
# nf5:
python lab10reg.py ids_from_packet
# node0:
python send_ids.py 0.0 0.0 0.02 0.07 0.01 0.0 0.008 0.07 0.0 0.0 0.217
```

**Round 4 -- Normal (logged in, high same-srv-rate, stable host):**
```bash
# nf5:
python lab10reg.py ids_from_packet
# node0:
python send_ids.py 0.0 0.0 1.0 0.0 1.0 1.0 1.0 0.0 0.0 0.01 0.008
```

**Round 5 -- Attack (zero bytes, high diff-srv-rate, scanning pattern):**
```bash
# nf5:
python lab10reg.py ids_from_packet
# node0:
python send_ids.py 0.0 0.0 0.06 0.06 0.05 0.0 0.02 0.05 0.0 0.0 0.5
```

### Part 4: Show Dataset (~15 sec)

On dev machine (PowerShell):
```powershell
Get-Content datasets/KDDTrain+.txt -TotalCount 3
(Get-Content datasets/KDDTrain+.txt).Count
```

### Part 5: Train the Model (~1 min)

```powershell
& "C:\Users\shao4\AppData\Local\Python\bin\python3.14.exe" scripts/train_ids.py
```
(Shows feature selection, epoch 1..50, accuracy, BF16 evaluation, output files)

### Part 6: Show Trained Weights (~15 sec)

```powershell
Get-Content programs/gpu/data_ids_trained_weights.json -TotalCount 30
```

---

## Audio Transcript (read as single voiceover)

This is Lab 10. I will demonstrate end-to-end ML-based network intrusion detection running on our custom network processor on the NetFPGA. The FPGA is already programmed with the same bitfile from Lab 8 -- no hardware changes were needed. The terminal on the left is the FPGA host, and the terminal on the right is node0, which sends network packets.

First, I will load the trained IDS neural network onto the GPU coprocessor. This writes 211 instructions into the GPU instruction memory and 383 data words into the GPU data memory, including all the trained weights and biases. Everything is loaded at runtime via PCI registers.

Now I will run several classification rounds, alternating between attack and normal traffic patterns. Each round, I start the packet receiver on the FPGA host, then send a feature vector from node0 as a UDP packet. The 11 features describe network connection statistics -- things like source bytes, destination bytes, same-service rate, and connection counts. The features are converted to BFloat16 and sent over the network to the NetFPGA.

The first sample represents suspicious traffic with patterns typical of port scanning: low same-service rate and unusual service diversity. The GPU classifies it as ATTACK.

The second sample represents normal traffic: high same-service rate, low error rates, and moderate host counts, typical of regular web browsing. The GPU classifies it as NORMAL.

I will continue with a few more samples. The third has high connection count and low same-service rate, another attack pattern. The fourth is a logged-in session with stable host behavior, which is normal. And the fifth has zero bytes transferred with high service diversity, a scanning pattern that the model recognizes as an attack.

These are not random numbers. Each feature vector represents real network connection statistics from the NSL-KDD dataset. The neural network learned to distinguish attack patterns from normal patterns during training, based on how these 11 features correlate with known intrusion types.

Now I will show the training side. This is the NSL-KDD dataset, a standard benchmark for intrusion detection with about 126,000 training samples. I will run the training script, which selects the top 11 features by importance analysis, trains an 11-16-8-2 MLP for 50 epochs, and then quantizes all weights to BFloat16. After training, the weights are exported as a JSON file containing all 346 parameters and the normalization parameters. These are then converted to hex format for loading into the GPU data memory, and the GPU kernel hex for the instruction memory was written in our custom assembly language.
