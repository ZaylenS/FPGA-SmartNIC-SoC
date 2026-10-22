# Project Milestone 1 Demo Video Script

**Extends: [Lab 10 Demo Script](demo_script.md)**

**Duration: ~5-6 minutes. Audio recorded separately with OBS.**

---

## Pre-Recording Setup

1. FPGA programmed on nf6: `nf_download nf2_top_par.bit`
2. Files deployed:
   - nf6 (`~/zil_testing_folder/`): lab10reg.py, lab9reg.py, ann_ids_11_16_8_2.hex, data_ids_trained.hex, test_features.csv, ann_ids_11_16_8_2.asm, send_ids.py
   - nf7 (`~/`): send_ids.py, test_features.csv
3. Three windows: left = nf6, right = nf7, bottom = dev machine (PowerShell)
4. Model NOT pre-loaded (ids_load will be shown live)

---

## Video Actions

### Part 1: Show Architecture (~30 sec)

On nf6, show the kernel header (the assembly "spec"):
```bash
sed -n '1,15p' ann_ids_11_16_8_2.asm
```

Then show a few lines of the inner loop:
```bash
sed -n '48,58p' ann_ids_11_16_8_2.asm
```

### Part 2: Load Model (~20 sec)

On nf6:
```bash
python lab10reg.py ids_load
```

### Part 3: Single Packet -- Attack (~40 sec)

On nf6:
```bash
python lab10reg.py ids_from_packet
```

On nf7:
```bash
python send_ids.py
```

Wait for classification result: should say ATTACK.

### Part 4: Single Packet -- Normal (~30 sec)

On nf6:
```bash
python lab10reg.py ids_from_packet
```

On nf7 (high same-srv-rate, logged in, stable host):
```bash
python send_ids.py 0.0 0.0 1.0 0.0 1.0 1.0 1.0 0.0 0.0 0.01 0.008
```

Wait for classification result: should say NORMAL.

### Part 5: Show the Sender Script (~15 sec)

On nf6, show BF16 conversion in the sender:
```bash
sed -n '43,46p' send_ids.py
```

### Part 6: Batch Inference with Accuracy (~1 min)

On nf6:
```bash
python lab10reg.py ids_batch_packets 20 test_features.csv --no-response
```

On nf7:
```bash
python send_ids.py --csv test_features.csv --delay 0.5
```

Wait for all 20 to process. The summary with confusion matrix prints automatically.

### Part 7: Show Results CSV (~15 sec)

On nf6:
```bash
head -5 ids_batch_results.csv
```

### Part 8: Training (~1 min)

On dev machine:
```powershell
& "C:\Users\shao4\AppData\Local\Python\bin\python3.14.exe" scripts/train_ids.py
```

(Shows feature selection, training epochs, accuracy, BF16 quantization, export)

### Part 9: Show Trained Weights (~15 sec)

On dev machine:
```powershell
Get-Content programs/gpu/data_ids_trained_weights.json -TotalCount 15
```

---

## Audio Transcript

This is our project milestone 1 demo. I am showing end-to-end ML-based intrusion detection running on our network processor on the NetFPGA.

First I am looking at the GPU kernel. It is an 11-16-8-2 MLP written in our custom assembly language -- 11 input features, two hidden layers, and 2 output classes. The inner loop uses 2-neuron interleaving, which means I process two neurons at the same time within each loop iteration. The reason is that our GPU pipeline has no result forwarding, so there is a 4-cycle stall every time an instruction reads a value that the previous instruction just wrote. By interleaving two independent neurons, the second neuron's loads and FMAs fill the first neuron's stall slots, so instead of one FMA every 8 cycles, I get two FMAs in about 14 cycles. The full inference runs in about 2400 cycles.

Next I load the trained model onto the FPGA. This writes 211 instructions into GPU instruction memory, and 383 words of weights and biases into data memory, all through PCI registers at runtime.

Then I run a single classification. I start the receiver on the FPGA host, and send 11 features from node0 as a UDP packet. The features are things like source bytes, connection count, and same-service rate from the NSL-KDD dataset. The FPGA extracts the features from the FIFO, loads them into GPU data memory, runs the kernel, and the result comes back as ATTACK. The logit values show the model is confident -- attack logit is 8.8, normal is negative 5.5.

After that I send a normal sample -- high same-service rate, user logged in, stable host behavior. The GPU classifies it as NORMAL.

Here I am showing the BF16 conversion in the sender script. A float is 4 bytes in IEEE 754. BF16 takes just the top 2 bytes -- the sign, exponent, and top 7 bits of mantissa. That is what these two lines do: pack the float, then take byte 0 and byte 1. This matches how the GPU hardware truncates.

Then I run batch inference on 20 test samples. The sender transmits one packet every half second, and the receiver classifies each one and compares against the ground truth label. At the end it prints a confusion matrix. The accuracy on this small test set is 75%, with 85% precision on attack detection. The per-sample inference time averages about 5 to 6 milliseconds, mostly PCI overhead -- the GPU kernel itself takes about 20 microseconds at 125 MHz. These results get saved to a CSV.

Finally, the training side. The script downloads NSL-KDD, selects the top 11 features by random forest importance, trains for 50 epochs with SGD, and quantizes all weights to BFloat16. The BF16 model gets about 76% accuracy on the full test set. The exported hex file is what I loaded into GPU data memory earlier.

The accuracy is decent for a first pass, and there is room to improve it -- longer training, wider layers, more features. The main result for this milestone is that the full pipeline works: packets come in from the network, the GPU classifies them, and results are reported, all on the NetFPGA with no RTL changes from Lab 8.
