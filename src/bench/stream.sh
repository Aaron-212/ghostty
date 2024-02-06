#!/usr/bin/env bash
#
# This is a trivial helper script to help run the stream benchmark.
# You probably want to tweak this script depending on what you're
# trying to measure.

# Options:
# - "ascii", uniform random ASCII bytes
# - "utf8", uniform random unicode characters, encoded as utf8
DATA="ascii"
SIZE="25000000"

# Uncomment to test with an active terminal state.
#ARGS=" --terminal"

# Generate the benchmark input ahead of time so it's not included in the time.
./zig-out/bin/bench-stream --mode=gen-$DATA | head -c $SIZE > /tmp/ghostty_bench_data

hyperfine \
  --warmup 10 \
  -n memcpy \
  "cat /tmp/ghostty_bench_data | ./zig-out/bin/bench-stream --mode=noop${ARGS}" \
  -n scalar \
  "cat /tmp/ghostty_bench_data | ./zig-out/bin/bench-stream --mode=scalar${ARGS}" \
  -n simd \
  "cat /tmp/ghostty_bench_data | ./zig-out/bin/bench-stream --mode=simd${ARGS}"
