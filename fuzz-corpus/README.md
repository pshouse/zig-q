# zig-q fuzz corpus

Published deterministic fuzz failures for the REPL harness (`zig build fuzz`).

## Reproduce a failure

When a fuzz iteration fails, the harness prints the world seed, fuzz seed, and iteration index. Re-run with:

```bash
zig build fuzz -- <iterations> <fuzz_seed> <world_seed>
```

Example (defaults: 10000 iterations, fuzz seed 0, world seed 42):

```bash
zig build fuzz -- 10000 0 42
```

## Corpus entries

No published failures for v1.0.0. This directory is reserved for future repro scripts and seed notes.