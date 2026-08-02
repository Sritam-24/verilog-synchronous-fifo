# Synchronous FIFO (8-bit x 16-depth) — Verilog / Vivado

A parameterized, single-clock synchronous FIFO with circular addressing and
dynamic full/empty flag generation, targeted at Xilinx Vivado.

## Files

| File                | Description                                              |
|---------------------|-----------------------------------------------------------|
| `sync_fifo.v`        | RTL: parameterized synchronous FIFO module                |
| `tb_sync_fifo.v`      | Self-checking testbench — 12 structured test cases         |
| `flowchart.jpg`       | Per-clock-cycle operational flowchart                     |
| `circuit_diagram.jpg` | Block/circuit diagram of the datapath and control logic   |
| `README.md`           | This file                                                  |

## Module: `sync_fifo`

### Parameters
| Parameter    | Default | Description                              |
|--------------|---------|-------------------------------------------|
| `DATA_WIDTH` | 8       | Width of each data word                   |
| `DEPTH`      | 16      | Number of storage locations (power of 2)  |
| `ADDR_WIDTH` | `$clog2(DEPTH)` | Derived, address width for memory  |

### Ports
| Port         | Dir | Width          | Description                          |
|--------------|-----|----------------|----------------------------------------|
| `clk`        | in  | 1              | System clock                           |
| `rst_n`      | in  | 1              | Active-low, synchronous reset          |
| `wr_en`      | in  | 1              | Write enable                           |
| `din`        | in  | `DATA_WIDTH`   | Write data                             |
| `full`       | out | 1              | FIFO full flag                         |
| `rd_en`      | in  | 1              | Read enable                            |
| `dout`       | out | `DATA_WIDTH`   | Read data (registered)                 |
| `empty`      | out | 1              | FIFO empty flag                        |
| `fifo_count` | out | `ADDR_WIDTH+1` | Current occupancy (debug/status)       |

## Design Notes

- **Memory**: a `mem[0:DEPTH-1]` register array, inferable as Vivado
  distributed RAM or Block RAM depending on synthesis settings.
- **Pointers**: `wr_ptr` and `rd_ptr` are `ADDR_WIDTH+1` bits wide. The
  lower `ADDR_WIDTH` bits form the circular memory address; the extra MSB
  ("wrap bit") toggles every time a pointer wraps past the end of memory.
  This is the standard technique for disambiguating full vs. empty without
  needing a separate up/down counter.
  - `empty = (wr_ptr == rd_ptr)` — address **and** wrap bit match.
  - `full  = (wr_addr == rd_addr) && (wrap bits differ)` — same address,
    but the write pointer has lapped the read pointer exactly once.
- **Overflow/underflow protection**: writes are internally qualified with
  `wr_en & ~full`, and reads with `rd_en & ~empty`, so asserting `wr_en`
  while full (or `rd_en` while empty) is safely ignored rather than
  corrupting the memory or pointers.
- **Read timing**: `dout` is registered, so read data appears one clock
  after `rd_en` is asserted (standard for Block RAM inference).

## Testbench: `tb_sync_fifo`

Self-checking, with a running `errors` counter and pass/fail printed per
check. 12 structured test cases:

1. **Reset behavior** — flags and `dout` correctly initialized.
2. **Single write** — `empty` deasserts.
3. **Single read** — data integrity, `empty` reasserts after drain.
4. **Write sequencing** — burst of writes, `fifo_count` tracks correctly.
5. **Read sequencing** — burst of reads, FIFO ordering preserved.
6. **Fill to full** — `full` asserts exactly at `DEPTH` writes.
7. **Overflow handling** — write while full is dropped, state unchanged.
8. **Drain to empty** — `empty` asserts exactly at 0 occupancy, FIFO order verified end-to-end.
9. **Underflow handling** — read while empty is dropped, `dout` holds last value.
10. **Wrap-around** — write/read sequence forced across the physical end
    of the memory array, verifying pointer wrap logic.
11. **Simultaneous read+write (mid-fill)** — occupancy stays constant,
    correct (oldest) data returned.
12. **Simultaneous read+write (while full)** — FIFO remains full,
    occupancy stays at `DEPTH`, correct data returned (no corruption).

## How to Run in Vivado

1. Create a new RTL project (or add to an existing one).
2. Add `sync_fifo.v` as a design source.
3. Add `tb_sync_fifo.v` as a **simulation** source.
4. Set `tb_sync_fifo` as the simulation top module.
5. Run Behavioral Simulation.
6. Check the Tcl console / log for `[PASS]` / `[FAIL]` lines and the final
   `ALL 12 TEST CASES PASSED` summary.

Alternatively, from the command line with the Vivado simulator:
```
xvlog sync_fifo.v tb_sync_fifo.v
xelab tb_sync_fifo -s fifo_sim
xsim fifo_sim -R
```

## Diagrams

- **`flowchart.jpg`** walks through what happens on every rising clock
  edge: reset check, sampling `wr_en`/`rd_en`, full/empty gating for
  overflow/underflow protection, pointer updates, and flag recomputation.
- **`circuit_diagram.jpg`** shows the datapath: write/read pointer
  registers, their incrementers, the shared memory array, the registered
  data output path, and the combinational full/empty flag logic.
