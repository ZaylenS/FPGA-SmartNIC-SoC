# Feasible Application Domains for a SmartNIC-Accelerated ANN on NetFPGA

## System constraints that strongly shape the project scope

Your current network processor is already a strong “SmartNIC-like” platform in the sense that it can (a) intercept packets in the datapath, (b) stall forwarding while computing, and (c) return a modified packet. In the provided lab integration, the packet interception is implemented with a convertible FIFO built from a dual-port BRAM sized for exactly one packet: **256 entries × 72 bits per entry** (64-bit data + 8-bit control). fileciteturn3file0 Each packet’s first word is a header word (typically `ctrl = 0xFF`) containing a `word_length` field, and the rest of the words are payload with `ctrl = 0x00`. fileciteturn3file9 This makes a clean unit of work for “one inference per packet,” but it also means throughput is naturally bounded unless you extend buffering.

The compute side is split into a small ARM-compatible CPU and a SIMD “GPU” coprocessor. In the shared architecture spec, the CPU is a 4-thread barrel processor (fine-grained multithreading) with a restricted ARM-like ISA; importantly for ML, the CPU **does not implement multiply**, and it does not include hazard detection/forwarding (relying instead on thread interleaving to reduce hazards). fileciteturn2file2 That makes the CPU a poor candidate for dense linear algebra, but still useful for control-oriented packet munging and simple integer preprocessing.

The GPU coprocessor is the right place for ANN inference. It is explicitly designed around **4-lane SIMD over 64-bit registers**, and its local memories are fixed at **1024×32-bit IMEM** and **1024×64-bit DMEM**. fileciteturn3file12 With DMEM at 1024×64-bit, you have **8 KiB total** for some combination of: input features, intermediate activations, weights, and output scores. fileciteturn3file12 The supported opcode set includes SIMD `MUL`, BF16 `FMA`, and a `RELU` activation, which is enough to implement small MLPs and “dot-product + threshold” classifiers. fileciteturn3file12

Data motion between the FIFO BRAM and GPU DMEM is handled by a DMA engine that runs in GPU mode. The shared architecture describes it as a short FSM with a one-cycle setup state and then **1 word per cycle** transfer. fileciteturn3file3 The integration guide shows the complete operational pattern: wait for packet buffered, switch to GPU mode, DMA FIFO→GPU, run kernel, DMA GPU→FIFO, switch back to FIFO mode, and drain the modified packet. fileciteturn3file11

Two practical engineering constraints matter a lot when picking a domain:

- **Single-packet buffering**: while the CPU/GPU is active, the FIFO’s `in_rdy` is gated so new packets cannot be safely accepted (otherwise packet writes would corrupt BRAM during processing). fileciteturn1file1 This is great for deterministic “stop-the-world” low-latency compute demonstrations, but it discourages any design that assumes continuous high-throughput streaming unless you add buffering or restructure the datapath.
- **Timing/resource headroom is asymmetric**: synthesis reports show slices are already high (example report shows 87% slices used), while BRAM and multiplier resources have more headroom. fileciteturn3file9 The GPU decode stage is also reported as a critical timing path with many violations (but functionally working in the lab context). fileciteturn3file9 This pushes you toward “do more with existing units,” not “add big new logic.”

Finally, the course deliverables themselves strongly incentivize a “small, demonstrable end-to-end pipeline” rather than a large model: Lab 8 and Lab 9 both emphasize system integration, test software, and a demo—Lab 9 explicitly allows the solution to be “as simple as the dot product of two very large vectors” mapped to the Arm core + GPU/tensor core, driven by a host program that sends packets with the data. fileciteturn3file6 The lab handouts also stress disciplined GitHub commit history and a demo video. fileciteturn3file1turn3file6

Because these constraints are intrinsic (8 KiB DMEM, one packet buffered, CPU without multiply), the most realistic interpretation of “image/audio/medical ML” on this platform is:

- either **pre-extract features off-NIC and run a tiny ANN on the NIC**, or
- use **very small inputs** (e.g., 28×28 grayscale) with an extremely small classifier (often linear / 1-hidden-layer at most).

## A general design template that makes all three domains feasible

A good “least-regret” architecture for any of the candidate domains is a split pipeline:

1. **Preprocessing / feature extraction (host or external process)**  
   For images: downsample, normalize, or use a pretrained CNN to output a compact embedding. For audio: compute MFCC/log-mel features, or use an audio embedding model. This step can be done on the host PC because your NIC-side CPU is not suited for heavy math (no multiply). fileciteturn2file2

2. **Feature packetization over NF2.1**  
   Pack features into 64-bit payload words (the bus is 64-bit data + 8-bit ctrl). fileciteturn3file9 BF16 activations map naturally: **4 BF16 values per 64-bit word** (or 4 int16 per word). fileciteturn3file9turn3file12

3. **On-NIC inference in GPU mode (Mode 2)**  
   Use the DMA engine to move payload words into GPU DMEM and run a kernel that computes either:
   - a dot product / logistic regression (one layer), or
   - a small MLP with ReLU (one hidden layer), using BF16 `FMA` and `RELU`. fileciteturn3file12turn3file3

4. **Return results in-packet**  
   Write classification scores or a class ID back into the packet (either overwriting part of the payload or appending right after the header), then drain the modified packet back into the datapath. fileciteturn3file11turn3file1

This template aligns unusually well with the “SmartNIC” concept in the literature: SmartNICs are widely characterized as NICs with integrated compute engines (CPUs/FPGAs/programmable pipelines) that offload packet processing and related functions from the host. citeturn6search0turn3search10 It also matches your lab wrapper’s explicit mode model (FIFO / CPU / GPU). fileciteturn2file2turn1file1

A key implication for project selection: **choose a domain where the meaningful part of the demo is the low-latency, packet-in → inference → packet-out loop**, not a claim of state-of-the-art accuracy from a large CNN.

## Manufacturing image inspection as a low-latency “quality gate”

The application story here is strong: automated visual inspection is a major manufacturing/maintenance use case for deep learning, and surveys show substantial academic and industrial activity around CNN-based inspection, transfer learning, and anomaly detection for quality assurance. citeturn3search0turn3search5 For small or medium manufacturers, the practical framing is “a fast quality gate that flags suspected defects early in the pipeline.”

The dataset-availability concern raised in your discussion is real, and it’s also reflected in why **industrial anomaly detection** is popular: in many factories, defect types change and defects are rare, so collecting large labeled datasets of *all* defect classes can be hard; anomaly detection methods often train on “normal only” and detect deviations. citeturn3search5turn6search5

### Open datasets that match the “acceptable vs defective” framing

Several well-known public datasets map cleanly to the binary decision “good vs defective,” either directly or with minimal relabeling:

- **MVTec AD**: explicitly designed for industrial inspection anomaly detection, with **15 object/texture categories** and **defect-free training images** plus a test set containing both defective and defect-free images; it includes pixel-precise ground truth masks for anomalies. citeturn6search1turn6search5turn6search16  
  This is a particularly good match if you adopt “normal vs anomalous” as your binary classification task.
- **KolektorSDD**: strongly imbalanced but realistic: **399 images total** with **52 defective** and **347 non-defective** images; the official dataset page also documents the native image sizes and a recommended resize for training. citeturn6search2turn6search17  
  This is a good match for “rare defect” realism, though class imbalance will need handling.
- **DAGM 2007** (industrial optical inspection competition data): includes many non-defective “background texture” images and a smaller set of defective images with exactly one labeled defect per defective image; it is synthetic but designed to resemble real inspection problems. citeturn2search12turn2search16  
  This can be attractive for a course project because it’s easier to scope and label.

image_group{"layout":"carousel","aspect_ratio":"16:9","query":["MVTec AD anomaly detection dataset example defect images","KolektorSDD commutator surface defect example","DAGM 2007 industrial inspection dataset defect examples","industrial visual inspection surface defect dataset example images"],"num_per_query":1}

### Model sizing: why full CNN inference is unrealistic on your NIC

Even “small” CNNs used as backbone feature extractors in mobile/edge settings are far too large to fit into 8 KiB:

- **SqueezeNet** explicitly targets “<0.5 MB model size” and far fewer parameters than AlexNet, but <0.5 MB is still two orders of magnitude larger than 8 KiB. citeturn5search1
- **MobileNets** are designed for mobile/embedded vision using depthwise separable convolutions, but they are still multi-layer CNNs typically described in the literature as “lightweight deep neural networks,” not “8 KiB SRAM networks.” citeturn5search12turn5search0

So the practical manufacturing vision approaches on your platform are:

- **Option A: Host-side feature extractor + NIC-side tiny classifier**  
  Use a pretrained CNN (e.g., MobileNet or similar) off-NIC to generate a compact embedding and send (say) 64–128 BF16 features per image to the NIC, then run a 1–2 layer MLP on the NIC. This respects your “reuse an existing open-source ANN/CNN and focus on system optimization” direction.
- **Option B: Tiny “direct” classifier on downsampled images**  
  Downsample images to something like 28×28 or 32×32 grayscale and run a linear classifier (or extremely small MLP) directly. This makes the demo feel more “image processing,” but it risks weaker accuracy and may require more careful training to avoid trivial failure.

Given your GPU instruction set includes BF16 `FMA` and `RELU`, a realistic target would be a **single hidden-layer MLP** where `input_dim × hidden_dim` is kept small enough for weights + activations to fit in 8 KiB. fileciteturn3file12turn3file12

## Streaming audio and signal processing as “packet-native” inference

Your team’s discussion correctly identified a unique alignment here: audio features can be computed per short window, naturally packetized, and classified with tight latency. This resembles common edge/TinyML workloads; for example, keyword spotting (KWS) is a classic “small input → small model → low latency” task used in embedded ML benchmarks. citeturn3search3turn1search0

Two audio directions stand out as particularly compatible with your system:

### Keyword spotting and event classification using public speech/audio datasets

- **Speech Commands** (Pete Warden): a widely used KWS dataset intended for training/evaluating models that detect a small vocabulary of spoken words. citeturn1search0turn1search20  
  Public dataset mirrors report that v0.02 contains **105,829 audio files**. citeturn0search6  
- **ESC-50**: a standard environmental sound classification benchmark of **2,000 recordings across 50 classes**. citeturn1search9turn1search1  
- **UrbanSound8K**: an urban sound dataset of **8,732 labeled excerpts** across **10 classes** (commonly cited from the dataset’s release materials and mirrors). citeturn1search14turn1search6

For a semester scope, Speech Commands is usually the best fit because (a) it’s designed for limited-vocabulary detection and (b) binary or small-class subsets are easy to define (e.g., “yes vs no”). citeturn1search0turn5search15

### Industrial machine sound anomaly detection, which also supports a manufacturing narrative

If you want an audio domain that still feels like “factory quality / maintenance,” the **MIMII dataset** is a strong candidate: it is explicitly curated for malfunctioning industrial machines (valves, pumps, fans, slide rails) with both normal and anomalous recordings, published for machine monitoring research. citeturn7search0turn7search5 The DCASE community’s anomalous sound detection tasks frame this as “normal vs anomalous” detection and emphasize the practical need to detect faults from audio for condition monitoring. citeturn7search7turn7search3

This direction has a nice advantage for your NIC: it matches your “one packet = one inference” architecture well because you can define one packet as “one window’s features,” classify it, and return a result. fileciteturn3file9turn3file11

image_group{"layout":"carousel","aspect_ratio":"16:9","query":["log-mel spectrogram keyword spotting example","MFCC feature diagram audio classification","Speech Commands dataset spectrogram yes no example","industrial machine sound anomaly detection spectrogram example"],"num_per_query":1}

### Practical model choices that fit in 8 KiB DMEM

Audio is rarely classified directly from raw waveform in tiny systems; typical pipelines transform waveform → time-frequency features (e.g., log-mel spectrogram, MFCC), then apply a small classifier. The Speech Commands paper itself is centered on building models for small keyword detection tasks (rather than full ASR), and the TensorFlow tutorials commonly demonstrate spectrogram-based pipelines for this dataset. citeturn1search0turn5search15

For your NIC, the clean mapping is:

- Host computes a compact feature vector **N** (example: 64–128 BF16 values).
- NIC runs an MLP like **N → 16 → 2**, using BF16 FMA and ReLU. fileciteturn3file12turn3file12

This is feasible in DMEM because the dominant weight matrix is `N×16` BF16 values (2 bytes/value). With `N=128`, that’s 2048 weights ≈ 4096 bytes, leaving room for the second layer, biases, and activations within the 8 KiB budget. The ability to pack 4 BF16 values per 64-bit lane-aligned word also makes the DMA and memory layout clean. fileciteturn3file12turn3file3

If you want to leverage existing embedding models without implementing them on your NIC, a standard approach is “pretrained embedding + small head.” The TensorFlow documentation for **YAMNet** describes it as a pretrained network that predicts 521 audio event classes and provides embeddings that can be reused for transfer learning. citeturn1search11turn1search3 That said, YAMNet-style embeddings are commonly 1024-D in practice; for your NIC you’d likely want post-processing (e.g., PCA or selecting a smaller intermediate representation) to keep `N` under ~128 for a multi-layer head.

## Medical and vision-based detection ideas with careful scoping

The medical direction is compelling and socially meaningful, but it’s also the easiest to accidentally overscope because “detection” in medical imaging often implies full pipelines (segmentation, localization, multi-stage diagnostic workflows).

A more feasible scope is **medical image classification** (binary or small multiclass) where the NIC only runs the final small ANN, and everything else is treated as preprocessing and dataset handling.

### Public datasets that support “small classification” tasks

- **MedMNIST v2** is a purpose-built educational benchmark: a collection of standardized biomedical image datasets where the 2D images are preprocessed to **28×28** and labeled for classification, designed to reduce domain barriers for learning and benchmarking. citeturn6search7turn6search18turn0search3  
  This is unusually well matched to your constraints because 28×28 inputs are small enough that even a linear classifier is plausible in 8 KiB.
- **PatchCamelyon (PCam)** is a large patch-based histopathology dataset for metastatic tissue classification with **327,680 96×96 color patches** and binary labels. citeturn4search4turn4search15  
  This is a well-known “cancer-related classification” benchmark, but 96×96×3 is too large for direct on-NIC inference unless you add an embedding step.
- **BreakHis** is a breast cancer histopathology dataset with thousands of images across magnifications; the official dataset page describes 9,109 images from 82 patients (with benign/malignant labels). citeturn4search3

Given your compute/memory limits, **MedMNIST-style inputs** or **precomputed embeddings** are the safest.

### Regulatory/ethics framing (important even for a class demo)

Even if your project is “for education only,” it’s helpful to explicitly state that:
- The demo is not a medical device, not clinically validated, and not intended for diagnosis.
- Medical ML is regulated when used in clinical decision-making contexts; the entity["organization","U.S. Food and Drug Administration","medical device regulator, us"] publishes guidance and “guiding principles” for AI/ML-enabled medical devices, including transparency expectations and lifecycle management considerations. citeturn4search2turn4search17  
  (You can cite this to justify why you deliberately constrain scope and claims.)

If you mention cross-jurisdictional principles, the FDA transparency principles are explicitly described as joint work with entity["organization","Health Canada","federal health agency, canada"] and the entity["organization","MHRA","uk medicines regulator"], which is useful context for “why we won’t position this as deployable clinical AI.” citeturn4search17

## Comparative feasibility and a defensible recommendation for project finalization

Your group’s three shortlisted domains—manufacturing image classification (from entity["people","Zilin","project teammate"]), audio/signal processing (from entity["people","Guillermo","project teammate"]), and medical/vision detection (from entity["people","Parker","project teammate"])—all become feasible if you accept a key scoping principle:

**The NIC runs only the compact ANN head; feature extraction is offloaded to the host or treated as preprocessing.** fileciteturn3file6turn2file2

Under that principle, the differentiators become: dataset availability, “demo clarity,” and how naturally each domain maps to packets.

### Why audio is usually the lowest-risk “end-to-end” story on this architecture

Audio has three advantages in your specific hardware/software context:

First, the “packet-native” story is unusually clean: you can make each packet carry one window’s features, run inference, write a class ID back, and forward/drain. This exactly matches your wrapper’s mode sequencing and DMA-based data movement. fileciteturn3file11turn3file3

Second, **model size pressure is lower** than vision if you choose compact features. A small MLP like 128→16→2 fits cleanly in DMEM, whereas even very small CNN backbones are orders of magnitude too large to run directly on-NIC. fileciteturn3file12turn5search1

Third, dataset availability is strong and “auditable”: Speech Commands (KWS) and MIMII (industrial machine anomalies) are both public and well-documented in the literature. citeturn1search0turn7search0turn7search5

A particularly defensible final-project statement (because it also ties to manufacturing) is:

**“Low-latency industrial machine anomaly detection over the network: host extracts compact audio features from a live/recorded stream, packets them to the SmartNIC, the NIC runs a tiny BF16 MLP for normal/anomalous classification, and returns the result in the packet with measured end-to-end latency.”** citeturn7search0turn7search7turn3file6

### When manufacturing image inspection is the better choice

Manufacturing vision becomes the better choice if your team strongly values (a) a direct “factory QC” customer story and (b) visual demo appeal. The most practical way to keep it feasible is to choose a dataset that naturally supports binary “normal vs defective” and does not force a bespoke defect taxonomy.

MVTec AD is the cleanest match for that constraint: defect-free training images + mixed test images, plus pixel-precise ground truth for anomalies. citeturn6search16turn6search5 KolektorSDD is also attractive if you want the “rare defect” realism, though it comes with imbalance. citeturn6search2turn6search17

A good “system-optimization focus” interpretation is:

- Run a pretrained vision embedding model off-NIC (transfer learning is widely used in industrial inspection to mitigate limited labeled data). citeturn3search4turn3search0
- Use the NIC to run the final “good vs defective” classifier head deterministically and measure packet-to-packet latency.

### Medical classification is feasible, but easiest to overscope

Medical classification is feasible if you pick datasets explicitly designed for lightweight experiments (MedMNIST) or you treat the input as already embedded. citeturn6search7turn4search15

The main risk is not “lack of data” (there is plenty), but “scope explosion” (moving from classification to detection/segmentation) and claim-making. FDA guidance materials make it clear that regulatory considerations revolve around safety/effectiveness evidence, lifecycle management, and transparency—none of which you can satisfy in a semester project—so you need to constrain claims and keep it as a technical demo. citeturn4search2turn4search17

### How this maps to your lab deliverables and what you can credibly claim

The labs by entity["people","Young Cho","course instructor"] emphasize (1) integration and refinement of CPU + GPU designs, (2) test software, and (3) a demo where packet data is processed and results are output as packets; Lab 9 explicitly calls out CUDA-style mapping and allows a dot-product-based solution. fileciteturn3file6turn3file1

A defensible set of evaluation claims that fits the class expectations is:

- **Correctness**: classification outputs match a host reference implementation on the same features.
- **Latency**: measure packet arrival → result packet emission (“stop-the-world” single-packet latency).
- **Throughput envelope**: characterize “packets per second” under the single-packet FIFO constraint (and explain that the design intentionally gates `in_rdy` outside FIFO mode to preserve correctness). fileciteturn1file1turn3file9
- **Engineering insight**: show the DMA/kernel split (DMA is 1 word/cycle after setup), and show that design choices (feature dimension, hidden size) are driven by the GPU’s fixed DMEM (1024×64-bit). fileciteturn3file3turn3file12

These claims are independent of whether you choose manufacturing, audio, or medical, and they directly demonstrate the “ANN-accelerated SmartNIC” concept rather than just building a model.

### Interviewee targeting under time pressure

If you still need interviewees quickly, the fastest path is to target roles where “latency + edge inference” is immediately legible:

- Manufacturing vision: shop-floor quality engineers or line supervisors are the natural fit, but if access is hard, you can instead interview someone who has deployed computer vision inspection in general manufacturing (even outside your exact product). The broad relevance of automated visual inspection in manufacturing/maintenance is well established in surveys, which can support your motivation even if interviews are limited. citeturn3search0turn3search5
- Audio: facility maintenance / condition-monitoring engineers align well with the MIMII/DCASE framing of machine-condition monitoring via anomalous sound detection. citeturn7search0turn7search7
- Medical: if you cannot access clinicians, focus interviews on medical imaging researchers/engineers; but keep claims framed as “educational classification demo” consistent with the broader regulatory environment for AI/ML medical devices. citeturn4search2turn4search17