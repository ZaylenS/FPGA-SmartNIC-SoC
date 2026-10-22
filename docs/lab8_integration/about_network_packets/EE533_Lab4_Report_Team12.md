# EE533 Lab4 Report

**Group 12**  
**Name:** Zilin Shao, YungChing Chang, Parker Chang

---

## Page 1

### Initial mini-IDS bitfile compiled

- Screenshot showing initial mini-IDS bitfile compilation.
- Screenshot showing related terminal/build output.

---

## Page 2

### NetFPGA environment

```bash
/sbin/ifconfig
```

### NetFPGA-based Linux Kernel IP Router

```bash
nf_download /home/netfpga/bitfiles/reference_nic.bit
```

- Screenshot showing NetFPGA environment.
- Screenshot showing reference NIC bitfile download/output.

---

## Page 3

### Ping other nodes from NetFPGA

- Screenshot showing successful ping tests.

### Test with iperf

### Send UDP datagrams from node0

- Screenshot showing `iperf` / UDP traffic test from node0.

---

## Page 4

### Receive UDP datagrams from node1

- Screenshot showing UDP datagrams received from node1.

### Use script to test the mini-IDS design

**Client node0 send, “WARNING” is proof of block**

- Screenshot showing the blocking behavior during the mini-IDS test.

---

## Page 5

### Server node1 receive, showing only ID 3 is proof of absence

- Screenshot showing receive-side result.

### Section 5i)

| Transmission Path | Client Node | Server Node | Measured Bandwidth | Packet Loss |
|---|---|---|---:|---:|
| Path A | Node 0 | Node 1 | 143 Mbits/sec | < 1% |
| Path B | Node 2 | Node 3 | 135 Mbits/sec | < 1% |
| Path C | Node 1 | Node 0 | 95.3 Mbits/sec | < 1% |
| **Average Throughput** | - | - | **124.4 Mbits/sec** | - |

---

## Page 6

### Conclusion

The automated iperf tests confirmed the NetFPGA reference router successfully forwards UDP traffic across all interfaces with an average throughput of >100 Mbps.

### Section 6

- Reference Nic had an Average 77.5% loss
- Reference Router had an Average 64.5% loss

- Screenshots showing the Section 6 test results.

---

## Page 7

### Section 7 Initial Attempt in Synthesizing and Testing Your Design

#### Trying to build a mini-IDS with logic analyzer

- Screenshot showing initial synthesis/testing attempt.

#### Debugging note

Encountered register address aliasing issues where dumped data remained static -> debugging of the register map configuration.

- Screenshot showing related debug output.

---

## Page 8

Reset ids’ registers, set bad patterns,  
check match signal count before sending a bad pattern -> 0,  
check match signal count after sending a bad pattern -> 11 (iperf sends multiple packets)

- Screenshot showing counter values before/after sending bad pattern.

### Logic analyzer dumped data table, observed bad pattern

- Screenshot showing dumped logic analyzer data table.

---

## Page 9

### For UDP mode, send random pattern and malicious pattern

- Screenshot showing UDP tests with random and malicious patterns.

### Packet drop verification

The iperf server (Node 1) shows active transfer for legitimate traffic, but remains completely silent during the malicious traffic test, confirming that the NetFPGA IDS blocked all UDP packets containing the signature.

- Screenshot showing packet drop verification.

### TCP mode behavior

On TCP mode, since the handshake packet contains no malicious pattern, it will establish the connection, but then silence (blocked).

- Screenshot showing TCP-mode behavior.

---

## Page 10

### Match counter observation

And we can observe matches increase.

- Screenshot showing increased `idsreg matches` values.

### Concurrent Traffic Test

Start UDP server on node1.

- Screenshot showing concurrent traffic test output.

---

## Page 11

Run all three streams at once, in the above screenshot we can see bandwidth reports for only two streams.

### IDS result

Ids matches also proves the third stream was dropped.

- Screenshot showing the concurrent run result.
- Screenshot showing `idsreg matches` output.

### GitHub commit

**Link:** <https://github.com/zilinsha/EE533-Lab4.git>

